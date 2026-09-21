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

part of 'web_server_host.dart';

/// Overlay / live-sync broadcasts attached while the server is bound.
extension WebServerHostStreams on WebServerHost {
  void _attachLiveRelays(ChatService? chatService, StreamHub? streamHub) {
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
    final kobold = _koboldService;
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
        final perfSpeed = chatService.lastPerfData?['last_process_speed'];
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
          'busyWith': chatService.isSummaryGenerating
              ? 'journal'
              : (chatService.isGrowthPassRunning ? 'growth' : null),
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
    // the connection flag flips (not on one-off request failures).
    final llm = _llmProvider;
    if (streamHub != null && llm != null) {
      void onLlmReady() {
        final ready = llm.composerConnectionReady;
        if (_lastLlmReady == ready) return;
        _lastLlmReady = ready;
        streamHub.broadcastChatUpdate();
      }

      _llmReadyListener = onLlmReady;
      _lastLlmReady = llm.composerConnectionReady;
      llm.addListener(onLlmReady);
      llm.openRouterService.addListener(onLlmReady);
    }

    // Image generation live progress → web clients: percent + (when the
    // backend streams one) the in-progress preview frame, so the web chat
    // shows the image coming to life like the desktop bubble. Preview frames
    // are throttled to ~1/s to keep the socket light.
    final imageGen = _imageGenService;
    if (streamHub != null && imageGen != null) {
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

  void _attachLibraryRelay(
    CharacterFacade characterFacade,
    StreamHub streamHub,
  ) {
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
    _characterRepository?.addListener(onLibraryChanged);
    _folderService?.addListener(onLibraryChanged);
    _groupChatRepository?.addListener(onLibraryChanged);
  }
}
