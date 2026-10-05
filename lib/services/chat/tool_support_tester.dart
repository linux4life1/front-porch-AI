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
// but WITHOUT ANY WARRANTY, without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/services/chat/pass_support.dart';
import 'package:front_porch_ai/services/chat/tool_eval_spec.dart';
import 'package:front_porch_ai/services/services.dart';

/// How long a model that answered nothing waits before it is asked again:
/// the first retry follows at once (the notification that comes next), the
/// later ones are spaced, and after the last the model is left alone until a
/// tap on the pill or another model. The engine's own log lines notify all
/// day long, so without the gaps a model that never answers was asked on every
/// one of them.
const List<Duration> kToolTestRetryGaps = [
  Duration.zero,
  Duration(seconds: 5),
  Duration(seconds: 15),
];

/// Actively answers "does the current model speak the tools protocol?" for
/// the chat sidebar's tool-calling pill — instead of the user only finding
/// out when a background pass silently falls back to text.
///
/// Fires one tiny tool-call request (a `report_ping` schema, a few tokens)
/// and records the verdict on the SAME [ToolTransportProbe] every eval
/// consumer shares, so a manual test and the passes never disagree. Runs
/// automatically when the backend/model identity changes and the backend is
/// ready (the "retest on model switch" contract), and on demand from the
/// pill. Skips while a chat generation is streaming — local engines serve
/// one request at a time.
///
/// A model that was meant to be tested is tested: nothing marks a model as
/// done until a question about it has been asked, a test that ends under
/// another identity (the model record moved while it ran) looks again at the
/// new one, and a test that settled nothing frees the model for another try.
class ToolSupportTester {
  ToolSupportTester({
    required this.probe,
    required this.fireToolEval,
    required this.getBackendIdentity,
    required this.isBackendReady,
    required this.isBusy,
    required this.onNotify,
    this.workerLaneReadyForPing,
    this.fetchMetadataToolVerdict,
    this.retryGaps = kToolTestRetryGaps,
    this.now = DateTime.now,
  });

  final ToolTransportProbe probe;
  final Object fireToolEval;
  final String Function() getBackendIdentity;
  final bool Function() isBackendReady;

  /// True while a chat generation is streaming — probing then would contend
  /// for the local engine's single generation slot.
  final bool Function() isBusy;

  /// Dual-GGUF: auto-ping must not `withWorkerLane` until the worker is
  /// resident and generation-ready. Null = always allowed (no swap).
  final bool Function()? workerLaneReadyForPing;
  final VoidCallback onNotify;

  /// Provider-metadata answer for "does the current REMOTE model support tool
  /// calls?" — true/false when OpenRouter/Nano-GPT `/models` metadata lists
  /// the model, null when it can't answer (local backend, generic host, entry
  /// miss, fetch failure). When it answers, the auto-test seeds the shared
  /// probe from it and skips the runtime ping entirely — free and instant.
  /// Null falls through to the ping, and the pill's tap-to-retest always
  /// fires the real ping (a live tool call is stronger evidence and may
  /// overrule stale metadata).
  final Future<bool?> Function()? fetchMetadataToolVerdict;

  /// See [kToolTestRetryGaps]. A seam so a test can shorten them.
  final List<Duration> retryGaps;
  final DateTime Function() now;

  bool _testing = false;
  bool _disposed = false;
  bool _checkedThisRun = false;
  String _lastAutoTestedIdentity = '';

  /// The identity whose tests came back without an answer, how many did, and
  /// when the next one may go.
  String _unansweredIdentity = '';
  int _unanswered = 0;
  DateTime _askAgainAfter = DateTime.fromMillisecondsSinceEpoch(0);

  bool get isTesting => _testing;

  /// True after a live ping finished for the current identity (not metadata).
  bool get checkedThisRun =>
      _checkedThisRun &&
      probe.supportFor(getBackendIdentity()) != ToolCallSupport.untested;

  ToolCallSupport get current => probe.supportFor(getBackendIdentity());

  void dispose() => _disposed = true;

  static const _pingTools = [
    {
      'type': 'function',
      'function': {
        'name': 'report_ping',
        'description': 'Report that you received this request.',
        'parameters': {
          'type': 'object',
          'properties': {
            'ok': {'type': 'boolean', 'description': 'Always true.'},
          },
          'required': ['ok'],
        },
      },
    },
  ];

  static const _pingPrompt =
      'Call the report_ping tool with ok set to true. Respond ONLY with the '
      'tool call — no other text.';

  bool _canAsk({bool force = false}) =>
      !_testing &&
      !isBusy() &&
      isBackendReady() &&
      (force || workerLaneReadyForPing == null || workerLaneReadyForPing!());

  /// Probe the current backend+model once and record the verdict.
  /// [force] forgets any existing verdict first (the pill's tap-to-retest).
  Future<void> test({bool force = false}) async {
    if (!_canAsk(force: force)) return;
    final identity = getBackendIdentity();
    if (force) {
      _unansweredIdentity = '';
      probe.reset(identity);
    }
    if (probe.supportFor(identity) != ToolCallSupport.untested) return;
    await _ask(identity);
  }

  /// One question to the model, and what to do with every way it can end.
  Future<void> _ask(String identity) async {
    _testing = true;
    onNotify();
    var settled = false;
    try {
      final resp = await invokeToolEval(
        fireToolEval,
        const ToolEvalSpec(
          prompt: _pingPrompt,
          tools: _pingTools,
          toolChoice: 'report_ping',
          maxLength: kPingToolMaxTokens,
          repeatPenalty: kScalarToolRepeatPenalty,
        ),
      );
      // Identity may have changed mid-flight (model switch during the probe);
      // only record a verdict for the identity that actually answered.
      if (getBackendIdentity() == identity) {
        _checkedThisRun = true;
        if (resp != null && resp.calls.isNotEmpty) {
          probe.markSupported(identity);
          settled = true;
        } else if (resp != null && resp.text.trim().isNotEmpty) {
          // Prose instead of a call — the model answered and chose words:
          // real capability evidence.
          probe.markXmlOnly(identity);
          settled = true;
        } else {
          // Null/empty answer: the clean-200 shape a KoboldCpp server-side
          // abort produces when it cuts down an in-flight call (the Scene
          // Guest "pill falls off" bug) — inconclusive, never a verdict.
          _checkedThisRun = false;
        }
      }
    } catch (e) {
      debugPrint('[ToolSupport] Probe failed: $e');
      // Transport failure (unreachable, torn-down client, timeout, busy
      // server) → leave untested: connectivity, not capability.
      if (getBackendIdentity() == identity && !isToolTransportFailure(e)) {
        _checkedThisRun = true;
        probe.markXmlOnly(identity);
        settled = true;
      }
    } finally {
      _testing = false;
      if (!settled) _leftUntested(identity);
      onNotify();
      // The model moved on while this ran: its answer was dropped, and the
      // model it moved to has not been asked yet.
      if (getBackendIdentity() != identity) Timer.run(onBackendMaybeChanged);
    }
  }

  /// A test for [identity] ended without a verdict: it may be tried again.
  void _leftUntested(String identity) {
    if (_lastAutoTestedIdentity == identity) _lastAutoTestedIdentity = '';
    // A test cut short because the model moved on says nothing about the
    // model it was for.
    if (getBackendIdentity() != identity) return;
    if (_unansweredIdentity != identity) {
      _unansweredIdentity = identity;
      _unanswered = 0;
    }
    _unanswered++;
    if (_unanswered <= retryGaps.length) {
      _askAgainAfter = now().add(retryGaps[_unanswered - 1]);
    }
  }

  bool _mayAsk(String identity) {
    if (identity != _unansweredIdentity) return true;
    if (_unanswered > retryGaps.length) return false;
    return !now().isBefore(_askAgainAfter);
  }

  /// Backend/model may have changed (LLMProvider or settings notified) —
  /// auto-test the new identity once it is ready. Idempotent and cheap:
  /// re-entering with the same identity is a no-op.
  void onBackendMaybeChanged() {
    if (_disposed) return;
    final identity = getBackendIdentity();
    if (identity == _lastAutoTestedIdentity) return;
    // One question at a time. One that ends under another identity looks
    // again by itself (see [_ask]).
    if (_testing) return;
    if (!isBackendReady() || isBusy()) return;
    if (workerLaneReadyForPing != null && !workerLaneReadyForPing!()) return;
    if (probe.supportFor(identity) != ToolCallSupport.untested) {
      _lastAutoTestedIdentity = identity;
      return;
    }
    if (!_mayAsk(identity)) return;
    // Marked only so the notifications that arrive during a metadata fetch do
    // not start a second test. [_seedOrTest] clears it on every way out that
    // leaves the model untested.
    _lastAutoTestedIdentity = identity;
    // Fire-and-forget; verdict lands on the shared probe and notifies the UI.
    _seedOrTest(identity);
  }

  /// Metadata first, ping second: when the provider's `/models` metadata can
  /// answer for this model, seed the shared probe from it (every eval gate
  /// and the pill then short-circuit with zero requests to the model itself);
  /// otherwise fall through to the runtime ping exactly as before.
  Future<void> _seedOrTest(String identity) async {
    final fetch = fetchMetadataToolVerdict;
    if (fetch != null) {
      bool? verdict;
      try {
        verdict = await fetch();
      } catch (e) {
        debugPrint('[ToolSupport] metadata fetch failed: $e');
        verdict = null;
      }
      // The model may have switched while the metadata fetch ran; a verdict
      // may also have landed from a pass or a manual test in the meantime.
      if (getBackendIdentity() != identity) {
        if (_lastAutoTestedIdentity == identity) _lastAutoTestedIdentity = '';
        Timer.run(onBackendMaybeChanged);
        return;
      }
      if (verdict != null &&
          probe.supportFor(identity) == ToolCallSupport.untested) {
        verdict ? probe.markSupported(identity) : probe.markXmlOnly(identity);
        return;
      }
      if (verdict != null) return;
    }
    // Nothing was tried when the engine got busy meanwhile: nothing is held
    // against the model, and the next notification asks again.
    if (!_canAsk()) {
      if (_lastAutoTestedIdentity == identity) _lastAutoTestedIdentity = '';
      return;
    }
    if (probe.supportFor(identity) != ToolCallSupport.untested) return;
    await _ask(identity);
  }
}
