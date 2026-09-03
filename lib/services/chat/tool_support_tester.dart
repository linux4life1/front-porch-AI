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

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/services/chat/pass_support.dart';
import 'package:front_porch_ai/services/chat/tool_eval_spec.dart';
import 'package:front_porch_ai/services/services.dart';

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
class ToolSupportTester {
  ToolSupportTester({
    required this.probe,
    required this.fireToolEval,
    required this.getBackendIdentity,
    required this.isBackendReady,
    required this.isBusy,
    required this.onNotify,
    this.fetchMetadataToolVerdict,
  });

  final ToolTransportProbe probe;
  final Object fireToolEval;
  final String Function() getBackendIdentity;
  final bool Function() isBackendReady;

  /// True while a chat generation is streaming — probing then would contend
  /// for the local engine's single generation slot.
  final bool Function() isBusy;
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

  bool _testing = false;
  bool _checkedThisRun = false;
  String _lastAutoTestedIdentity = '';
  String? _inFlightIdentity;

  bool get isTesting => _testing;

  /// True after a live ping finished for the current identity (not metadata).
  bool get checkedThisRun =>
      _checkedThisRun &&
      probe.supportFor(getBackendIdentity()) != ToolCallSupport.untested;

  ToolCallSupport get current => probe.supportFor(getBackendIdentity());

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

  /// Probe the current backend+model once and record the verdict.
  /// [force] forgets any existing verdict first (the pill's tap-to-retest).
  Future<void> test({bool force = false}) async {
    if (_testing || isBusy() || !isBackendReady()) return;
    final identity = getBackendIdentity();
    if (_inFlightIdentity == identity) return;
    if (force) probe.reset(identity);
    if (probe.supportFor(identity) != ToolCallSupport.untested) return;

    _testing = true;
    _inFlightIdentity = identity;
    onNotify();
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
        } else if (resp != null && resp.text.trim().isNotEmpty) {
          // Prose instead of a call — the model answered and chose words:
          // real capability evidence.
          probe.markXmlOnly(identity);
        } else {
          // Null/empty answer: the clean-200 shape a KoboldCpp server-side
          // abort produces when it cuts down an in-flight call (the Scene
          // Guest "pill falls off" bug) — inconclusive, never a verdict.
          // Leave untested and re-arm the auto-test so the next
          // backend-changed notify (or a pill tap) retries.
          _checkedThisRun = false;
          _lastAutoTestedIdentity = '';
        }
      }
    } catch (e) {
      debugPrint('[ToolSupport] Probe failed: $e');
      // Transport failure (unreachable, torn-down client, timeout, busy
      // server) → leave untested: connectivity, not capability — and re-arm
      // the auto-test so a later backend notify retries.
      if (getBackendIdentity() == identity && !isToolTransportFailure(e)) {
        _checkedThisRun = true;
        probe.markXmlOnly(identity);
      } else if (getBackendIdentity() == identity) {
        _lastAutoTestedIdentity = '';
      }
    } finally {
      if (_inFlightIdentity == identity) _inFlightIdentity = null;
      _testing = false;
      onNotify();
    }
  }

  /// Backend/model may have changed (LLMProvider or settings notified) —
  /// auto-test the new identity once it is ready. Idempotent and cheap:
  /// re-entering with the same identity is a no-op.
  void onBackendMaybeChanged() {
    final identity = getBackendIdentity();
    if (identity == _lastAutoTestedIdentity) return;
    if (_inFlightIdentity == identity) return;
    if (!isBackendReady() || isBusy()) return;
    if (probe.supportFor(identity) != ToolCallSupport.untested) {
      _lastAutoTestedIdentity = identity;
      return;
    }
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
      if (getBackendIdentity() != identity) return;
      if (verdict != null &&
          probe.supportFor(identity) == ToolCallSupport.untested) {
        verdict ? probe.markSupported(identity) : probe.markXmlOnly(identity);
        return;
      }
      if (verdict != null) return;
    }
    await test();
  }
}
