// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/image/image.dart';
import 'package:front_porch_ai/services/web/facade/facades.dart';
import 'package:front_porch_ai/services/web/host/web_host_services.dart';
import 'package:front_porch_ai/services/web/streaming/stream_hub.dart';

/// The live broadcasts a running web server pushes to every browser: the eval
/// overlay, generation status, connection state, speed test, image progress,
/// and the debounced library / settings live-sync. Owns its listeners and
/// timers; the host attaches them on start and calls [detach] on stop.
class WebLiveRelays {
  WebLiveRelays(this._storage, this._services);

  final StorageService _storage;

  /// The host's services, read when attaching and again when detaching.
  final WebHostServices _services;

  // Realism-eval overlay streaming: a ChatService listener that pushes the
  // accumulating eval text over the hub while the Realism Engine is thinking, so
  // the web shows the same live "processing" overlay the desktop does. Stored so
  // [detach] can remove it.
  VoidCallback? _realismListener;
  bool _wasEvaluatingRealism = false;
  bool _wasAwaitingChanceTime = false;
  bool _wasPendingImageReview = false;
  // A turn's last writes (the new swipe, chips) land while it settles, after
  // the stream's `done`; see the turn-settled broadcast in [attachLive].
  bool _wasTurnBusy = false;
  // Throttle/dedupe state for the processing broadcast: during evals every
  // ChatService notify (≤150ms apart) used to re-send the FULL accumulated
  // eval text — O(n²) bytes over the socket and a client re-render per frame,
  // which is a big part of the reported iPad stalls. Transitions always send;
  // text growth is rate-limited and unchanged payloads are skipped.
  DateTime _lastProcessingSent = DateTime.fromMillisecondsSinceEpoch(0);
  int _lastProcessingTextLen = -1;
  bool _lastProcessingVerifying = false;
  bool _lastProcessingObjective = false;

  // Image-gen progress relay (see the imageGen listener in [attachLive]).
  VoidCallback? _imageProgressListener;
  bool _wasImageGenerating = false;
  DateTime _lastImageProgressSent = DateTime.fromMillisecondsSinceEpoch(0);

  // Truthful generation-status relay (parity with the desktop status bar):
  // live prompt-reading progress parsed from the managed KoboldCpp console +
  // which background pass is holding the single local slot. Listens on BOTH
  // the ChatService (phase flips) and the KoboldService (live counts), plus
  // a 1s heartbeat timer: console lines arrive only once per BATCH, so
  // between them no notifier fires and the interpolated fraction would
  // freeze on web without the tick.
  VoidCallback? _genStatusListener;
  VoidCallback? _llmReadyListener;
  VoidCallback? _packBoardListener;
  VoidCallback? _speedTestListener;
  bool? _lastLlmReady;
  String? _lastLlmHint;
  Timer? _genStatusTicker;
  bool _wasBroadcastingGenStatus = false;
  DateTime _lastGenStatusSent = DateTime.fromMillisecondsSinceEpoch(0);

  // Near-instant library live-sync: one debounced listener attached to the
  // CharacterRepository, FolderService and GroupChatRepository (all
  // ChangeNotifiers). Because the desktop UI and the web facades mutate through
  // these same shared services, ANY library change — from the desktop app or a
  // web client — fans a single `library_changed` event out to every connected
  // browser so its library refreshes without a manual reload. Stored so [detach]
  // can remove and cancel them.
  VoidCallback? _libraryListener;
  Timer? _libraryDebounce;
  VoidCallback? _settingsListener;
  Timer? _settingsDebounce;

  /// The chat overlay, generation status, connection, speed test and image
  /// progress relays.
  void attachLive(StreamHub? streamHub) {
    final chatService = _services.chat;
    // Stream the Realism + Objective engines' "processing" state to the web
    // overlay. ChatService notifies (debounced ~150ms) as eval chunks arrive; we
    // only broadcast while something is actually processing, and emit one final
    // {active:false} so the overlay dismisses. Cheap no-op on every other notify
    // (just a couple of bool reads).
    if (chatService != null && streamHub != null) {
      void onProcessing() {
        final realism = chatService.isEvaluatingRealism;
        final objective = chatService.isCheckingCompletion;
        final active = realism || objective;
        if (active) {
          final verifying = chatService.isVerifyingRealism;
          final text = chatService.realismEvalStreamTextClean;
          final now = DateTime.now();
          // A phase transition (eval started, verifier flipped, objective
          // phase joined) always sends; otherwise only send when the eval
          // text actually grew AND the 300ms window elapsed. This turns the
          // ~6.6 full-payload frames/s of a long local eval into ≤3 delta-
          // worthy ones and drops the identical re-broadcasts entirely.
          final transition =
              !_wasEvaluatingRealism ||
              verifying != _lastProcessingVerifying ||
              objective != _lastProcessingObjective;
          final textChanged = text.length != _lastProcessingTextLen;
          if (transition ||
              (textChanged &&
                  now.difference(_lastProcessingSent).inMilliseconds >= 300)) {
            _lastProcessingSent = now;
            _lastProcessingTextLen = text.length;
            _lastProcessingVerifying = verifying;
            _lastProcessingObjective = objective;
            streamHub.broadcast({
              'event': 'processing',
              'active': true,
              'realism': realism,
              'objective': objective,
              'greeting': chatService.isProcessingGreeting,
              'verifying': verifying,
              'text': text,
            });
          }
        } else if (_wasEvaluatingRealism) {
          _lastProcessingTextLen = -1;
          streamHub.broadcast({'event': 'processing', 'active': false});
        }
        _wasEvaluatingRealism = active;

        // Chance Time: chaos parks sendMessage on a completer until the user
        // accepts their fate. Desktop pops its wheel from a ChangeNotifier flag;
        // web clients have no such hook, so announce the park (and its release)
        // here so the reveal modal can open/close. `data` carries the
        // pre-resolved event for an instant reveal; /api/chat/state.chanceTime
        // is the reconnect fallback. Edge-triggered — a couple of cheap reads on
        // every other notify.
        final awaitingChance = chatService.isAwaitingChanceTime;
        if (awaitingChance != _wasAwaitingChanceTime) {
          streamHub.broadcast(
            awaitingChance
                ? {
                    'event': 'chance_time',
                    'pending': true,
                    'data': ?chatService.webChanceTimeDisplay,
                  }
                : {'event': 'chance_time', 'pending': false},
          );
          _wasAwaitingChanceTime = awaitingChance;
        }
        // /image prompt review parked/resolved — poke clients to refetch state
        // so the web review modal opens/closes (same transition pattern as
        // Chance Time; the send request itself is blocked on the completer).
        final pendingReview = chatService.pendingImagePromptReview != null;
        if (pendingReview != _wasPendingImageReview) {
          streamHub.broadcast({'event': 'chat_updated'});
          _wasPendingImageReview = pendingReview;
        }
        // Turn fully settled. Web clients refetch on `done`, which fires when
        // the text stops streaming — before post-gen appends the new swipe
        // and chips — so without this a regenerated reply read "1/1" on the
        // phone until something else changed.
        final turnBusy = chatService.isGenerating || chatService.isSettlingTurn;
        if (_wasTurnBusy && !turnBusy) streamHub.broadcastChatUpdate();
        _wasTurnBusy = turnBusy;
      }

      _realismListener = onProcessing;
      chatService.addListener(onProcessing);
    }

    // Truthful generation status → web clients (parity with the desktop
    // status bar): live prompt-reading counts from the ACTIVE backend's
    // source (Kobold console, oMLX admin-stats poll, LM Studio runtime log
    // — resolved by chatService.activeLiveProgress), plus which background
    // pass (journal/growth) or queued request is holding the slot.
    // Throttled to ~2.5/s; one final {active:false} dismisses the line.
    // Plain remote backends never have fresh live counts, so clients fall
    // back to their plain indicator.
    final kobold = _services.kobold;
    if (streamHub != null && chatService != null) {
      void onGenStatus() {
        final generating = chatService.isGenerating;
        if (!generating) {
          if (_wasBroadcastingGenStatus) {
            _wasBroadcastingGenStatus = false;
            streamHub.broadcast({'event': 'gen_status', 'active': false});
          }
          return;
        }
        final now = DateTime.now();
        if (now.difference(_lastGenStatusSent).inMilliseconds < 400) return;
        _lastGenStatusSent = now;
        _wasBroadcastingGenStatus = true;
        final live = chatService.activeLiveProgress;
        final fresh = live != null && live.isFresh;
        // Server-side interpolation between per-batch updates (same math as
        // the desktop bar) so web clients get a moving fraction without
        // doing their own estimation.
        final measured = chatService.prefillMetricsAreMeasured;
        final speed = chatService.lastPerfData?['last_process_speed'];
        final perfSpeed = measured ? speed : null;
        final estFraction = fresh
            ? live.estimatedPromptFraction(
                tokensPerSecond: (perfSpeed is num && perfSpeed > 0)
                    ? perfSpeed.toDouble()
                    : null,
              )
            : null;
        streamHub.broadcast({
          'event': 'gen_status',
          'active': true,
          'phase': chatService.generationPhase.name,
          'elapsed': chatService.prefillElapsedSeconds,
          // 'journal' and 'growth' are named by the client; what has the
          // engine (the speed test) is sent in words.
          'busyWith': chatService.isSummaryGenerating
              ? 'journal'
              : (chatService.isGrowthPassRunning ? 'growth' : live?.heldBy),
          // Backend-reported queue depth — NOT attributable (may be someone
          // waiting on us), so clients state it neutrally (review finding).
          'queued': fresh ? live.waitingCount : 0,
          'promptCur': fresh ? live.promptCurrent : null,
          'promptTotal': fresh ? live.promptTotal : null,
          'promptDone': fresh && (live.promptFraction() ?? 0) >= 1.0,
          'estFraction': estFraction,
          'genCur': fresh ? live.genCurrent : null,
          'genTotal': fresh ? live.genTotal : null,
        });
      }

      _genStatusListener = onGenStatus;
      chatService.addListener(onGenStatus);
      // Kobold pushes console updates through notifyListeners; the polled
      // sources (oMLX / LM Studio) ride the 1s heartbeat below instead.
      kobold?.addListener(onGenStatus);
      // Heartbeat: keeps the interpolated fraction moving between console
      // lines. Cheap no-op whenever nothing is generating.
      _genStatusTicker = Timer.periodic(
        const Duration(seconds: 1),
        (_) => onGenStatus(),
      );
    }

    // Composer "No API connection" placeholder — push chat_updated only when
    // the connection flag or the reason it gives flips (not on one-off request
    // failures).
    final llm = _services.llm;
    if (streamHub != null && llm != null) {
      void onLlmReady() {
        final ready = llm.composerConnectionReady;
        final hint = llm.composerConnectionHint;
        if (_lastLlmReady == ready && _lastLlmHint == hint) return;
        _lastLlmReady = ready;
        _lastLlmHint = hint;
        streamHub.broadcastChatUpdate();
      }

      _llmReadyListener = onLlmReady;
      _lastLlmReady = llm.composerConnectionReady;
      _lastLlmHint = llm.composerConnectionHint;
      llm.addListener(onLlmReady);
      llm.openRouterService.addListener(onLlmReady);

      // The speed test's progress → the phone's overlay, as it changes (a
      // few times a step).
      final test = llm.koboldSpeedTest;
      if (test != null) {
        void onSpeedTest() => streamHub.broadcast({
          'event': 'speed_test',
          'speedTest': test.toJson(),
        });
        _speedTestListener = onSpeedTest;
        test.addListener(onSpeedTest);
      }
    }

    // Image generation live progress → web clients: percent + (when the
    // backend streams one) the in-progress preview frame, so the web chat
    // shows the image coming to life like the desktop bubble. Preview frames
    // are throttled to ~1/s to keep the socket light.
    final imageGen = _services.imageGen;
    if (streamHub != null && imageGen != null) {
      void onPackChanged() =>
          streamHub.broadcast({'event': 'expression_pack_changed'});
      _packBoardListener = onPackChanged;
      expressionPackBoard.addListener(onPackChanged);
      void onImageProgress() {
        final generating = imageGen.isGenerating;
        if (!generating && !_wasImageGenerating) return;
        if (!generating) {
          streamHub.broadcast({'event': 'image_progress', 'generating': false});
          _wasImageGenerating = false;
          return;
        }
        final now = DateTime.now();
        if (_wasImageGenerating &&
            now.difference(_lastImageProgressSent).inMilliseconds < 700) {
          return;
        }
        _lastImageProgressSent = now;
        final preview = imageGen.genPreview;
        // A1111 previews are PNG, ComfyUI's are typically JPEG — sniff the
        // magic bytes so the data URL declares the right mime.
        String? previewUrl;
        if (preview != null && preview.length > 2) {
          final mime = (preview[0] == 0xFF && preview[1] == 0xD8)
              ? 'image/jpeg'
              : 'image/png';
          previewUrl = 'data:$mime;base64,${base64Encode(preview)}';
        }
        streamHub.broadcast({
          'event': 'image_progress',
          'generating': true,
          'progress': ?imageGen.genProgress,
          'preview': ?previewUrl,
        });
        _wasImageGenerating = true;
      }

      _imageProgressListener = onImageProgress;
      imageGen.addListener(onImageProgress);
    }
  }

  void attachLibrary(CharacterFacade characterFacade, StreamHub streamHub) {
    // Library live-sync: broadcast a single debounced `library_changed` whenever
    // characters, folders or groups change (from the desktop or a web client),
    // so every browser refreshes its library near-instantly. Debounced ~150ms to
    // coalesce the multiple notifies a single op can fire (e.g. an import).
    void onLibraryChanged() {
      // Undebounced: the refetch this broadcast triggers must not be served
      // from a memo that predates the change, or a swapped portrait would
      // keep its old `v=` token and stay cached in the browser.
      characterFacade.invalidateAvatarVersions();
      _libraryDebounce?.cancel();
      _libraryDebounce = Timer(const Duration(milliseconds: 150), () {
        streamHub.broadcast({'event': 'library_changed'});
      });
    }

    _libraryListener = onLibraryChanged;
    // Background portrait probes that find a no-portrait placeholder ask for
    // one refetch through the same debounce.
    characterFacade.onPlaceholderPortraitsFound = onLibraryChanged;
    _services.characters?.addListener(onLibraryChanged);
    _services.folders?.addListener(onLibraryChanged);
    _services.groups?.addListener(onLibraryChanged);
  }

  /// Settings live-sync: one debounced `settings_changed` whenever a setting
  /// is written anywhere (the desktop or a web client), so a phone page that
  /// shows a setting's consequence (the clock-off line under Needs, the
  /// refractory words) refetches instead of keeping its first read.
  void attachSettings(StreamHub streamHub) {
    void onSettingsChanged() {
      _settingsDebounce?.cancel();
      _settingsDebounce = Timer(const Duration(milliseconds: 150), () {
        streamHub.broadcast({'event': 'settings_changed'});
      });
    }

    _settingsListener = onSettingsChanged;
    _storage.addListener(onSettingsChanged);
  }

  /// True while any relay is attached or a timer is pending.
  bool get isWired =>
      _realismListener != null ||
      _genStatusListener != null ||
      _llmReadyListener != null ||
      _speedTestListener != null ||
      _imageProgressListener != null ||
      _packBoardListener != null ||
      _libraryListener != null ||
      _settingsListener != null ||
      _genStatusTicker != null ||
      _libraryDebounce != null ||
      _settingsDebounce != null;

  /// Remove every relay from the services the host holds now, and cancel the
  /// heartbeat and debounce timers.
  void detach() {
    final chat = _services.chat;
    final llm = _services.llm;
    if (_realismListener != null) {
      chat?.removeListener(_realismListener!);
      _realismListener = null;
    }
    _wasEvaluatingRealism = false;
    _wasTurnBusy = false;
    if (_genStatusListener != null) {
      chat?.removeListener(_genStatusListener!);
      _services.kobold?.removeListener(_genStatusListener!);
      _genStatusListener = null;
    }
    _genStatusTicker?.cancel();
    _genStatusTicker = null;
    _wasBroadcastingGenStatus = false;
    if (_llmReadyListener != null) {
      llm?.removeListener(_llmReadyListener!);
      llm?.openRouterService.removeListener(_llmReadyListener!);
      _llmReadyListener = null;
    }
    if (_speedTestListener case final l?) {
      llm?.koboldSpeedTest?.removeListener(l);
      _speedTestListener = null;
    }
    _lastLlmReady = null;
    if (_packBoardListener != null) {
      expressionPackBoard.removeListener(_packBoardListener!);
      _packBoardListener = null;
    }
    _lastLlmHint = null;
    if (_imageProgressListener != null) {
      _services.imageGen?.removeListener(_imageProgressListener!);
      _imageProgressListener = null;
    }
    _wasImageGenerating = false;
    if (_settingsListener != null) {
      _storage.removeListener(_settingsListener!);
      _settingsListener = null;
    }
    _settingsDebounce?.cancel();
    _settingsDebounce = null;
    if (_libraryListener != null) {
      _services.characters?.removeListener(_libraryListener!);
      _services.folders?.removeListener(_libraryListener!);
      _services.groups?.removeListener(_libraryListener!);
      _libraryListener = null;
    }
    _libraryDebounce?.cancel();
    _libraryDebounce = null;
  }
}
