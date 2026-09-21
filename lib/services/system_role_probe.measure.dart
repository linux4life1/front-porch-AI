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

part of 'system_role_probe.dart';

extension _SystemRoleProbeMeasure on SystemRoleProbe {
  /// One three-arm measurement: true = honored, false = dropped, null =
  /// inconclusive (and therefore retryable). Owns every log line that quotes
  /// the numbers, because it is the only place that has them.
  Future<bool?> _measure(
    String identity,
    int attempt,
    Future<int?> Function(String system, String user) arm,
  ) async {
    try {
      // Short-circuit on the first arm that can't answer: a server that
      // failed once won't answer the rest either, and a probe that cannot
      // conclude must not spend three times the traffic proving it (nor hold
      // the engine slot through three timeouts).
      final baseline = await arm(kSystemRoleProbeMarker, _kProbePing);
      final inSystem = baseline == null || baseline <= 0
          ? null
          : await arm(
              '$kSystemRoleProbeMarker\n$kSystemRoleProbeFiller',
              _kProbePing,
            );
      final inUser = inSystem == null
          ? null
          : await arm(
              kSystemRoleProbeMarker,
              '$kSystemRoleProbeFiller\n\n$_kProbePing',
            );
      if (baseline == null || inSystem == null || inUser == null) {
        debugPrint(
          '[SystemRole] Probe inconclusive on $identity — assuming the '
          'system message works (attempt $attempt)',
        );
        return null;
      }
      final sysCost = inSystem - baseline;
      final refCost = inUser - baseline;
      if (refCost < kSystemRoleProbeMinRefTokens) {
        // The calibration arm did not move: this server's prompt_tokens are
        // not a real measurement (constant, rounded to a block, or padded to
        // a fixed size). Never guess a verdict from numbers that don't track
        // the payload.
        debugPrint(
          '[SystemRole] $identity reports unusable prompt_tokens '
          '(baseline $baseline, filler in user cost $refCost) — leaving it '
          'untested (attempt $attempt)',
        );
        return null;
      }
      final delivered = sysCost / refCost;
      if (delivered <= kSystemRoleDroppedRatio) {
        debugPrint(
          '[SystemRole] $identity DROPS the system message — the same filler '
          'cost $sysCost tokens in the system role vs $refCost in the user '
          'role (${(delivered * 100).round()}% delivered). Folding it into '
          'the user message so the character card still reaches the model',
        );
        return false;
      }
      if (delivered >= kSystemRoleHonoredRatio) {
        debugPrint(
          '[SystemRole] $identity delivers the system message '
          '($sysCost vs $refCost prompt tokens for the same filler)',
        );
        return true;
      }
      // Partial delivery we can't confidently name. Fail open rather than
      // fold a card into the user turn on a backend that mostly works.
      debugPrint(
        '[SystemRole] $identity delivered only '
        '${(delivered * 100).round()}% of the system filler — ambiguous, '
        'leaving it untested (attempt $attempt)',
      );
      return null;
    } catch (e) {
      // Fail open: an unreachable/annoyed server says nothing about the
      // template. The attempt is already counted, so this cannot spin.
      debugPrint('[SystemRole] Probe failed on $identity: $e');
      return null;
    }
  }

  /// One `max_tokens: 1` completion; returns the server-reported prompt token
  /// count, or null when the server did not report one.
  ///
  /// The client is parked on [run] for the duration so [reset] can close it —
  /// see [reset] for why waiting out the timeout instead is not an option.
  Future<int?> _promptTokens(
    String baseUrl,
    _ProbeRun run,
    String system,
    String user,
  ) async {
    if (run.cancelled) return null;
    final client = http.Client();
    run.client = client;
    try {
      final response = await client
          .post(
            Uri.parse('$baseUrl/v1/chat/completions'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'model': 'koboldcpp',
              'stream': false,
              'max_tokens': 1,
              'temperature': 0.1,
              'messages': [
                {'role': 'system', 'content': system},
                {'role': 'user', 'content': user},
              ],
            }),
          )
          .timeout(kSystemRoleProbeTimeout);
      if (response.statusCode != 200) return null;
      final json = jsonDecode(response.body);
      if (json is! Map) return null;
      final usage = json['usage'];
      if (usage is! Map) return null;
      return (usage['prompt_tokens'] as num?)?.toInt();
    } finally {
      if (identical(run.client, client)) run.client = null;
      client.close();
    }
  }
}

/// One attempt-chain for one identity. Its OBJECT identity is the run's
/// identity, which is what lets a late [SystemRoleProbe.reset] disown a probe
/// that is already on the wire without also disowning the fresh chain that
/// replaced it — the two are otherwise indistinguishable, since they share a
/// key, a base URL and a verdict slot.
class _ProbeRun {
  /// Set by [cancel]. Checked after every await that could have spanned a
  /// reset, so a disowned chain writes no verdict and issues no further arms.
  bool cancelled = false;

  /// The arm currently on the wire, parked here so it can be closed.
  http.Client? client;

  void cancel() {
    cancelled = true;
    client?.close();
    client = null;
  }
}

/// Backend+model identity key. It shares the model/path components used by the
/// tools probe, while that remote-capability probe additionally keys by API
/// endpoint. Switching either model or backend still re-probes by
/// construction.
///
/// Every component is a MUTABLE setting, so a caller must resolve this ONCE
/// when the model comes up and hold the string — never recompute it per
/// generation. Recomputing lets an unrelated settings edit (the remote model
/// name, a preset swap) silently move the key out from under a `dropped`
/// verdict, which turns the workaround off mid-run on a model still measured
/// to drop.
String systemRoleIdentityFor({
  required String backendName,
  required String remoteModelName,
  required String? modelPath,
}) => '$backendName|$remoteModelName|${modelPath ?? ''}';

/// The system content present in EVERY arm — short, and self-describing so it
/// can never be mistaken for user content if it surfaces in a log.
const String kSystemRoleProbeMarker =
    'This is an automated capability check from Front Porch AI. It measures '
    'whether this model actually receives system messages. No reply is '
    'needed and nothing here is part of any conversation.';

/// The bulk that moves between the system role (arm B) and the user role
/// (arm C). Deliberately large — ~200 words, which is 200+ tokens on every
/// tokenizer we have measured — so the differential dwarfs boundary-token
/// noise and clears [kSystemRoleProbeMinRefTokens] with room to spare.
final String kSystemRoleProbeFiller = _kFiller * 10;

const String _kFiller =
    'The warden keeps a ring of iron keys and remembers every face that has '
    'passed the threshold of the hall. ';

const String _kProbePing = 'Reply with ok.';

/// Verdict bands for `sysCost / refCost` — the share of an identical filler
/// the server charged for when it rode the system role instead of the user
/// role. A healthy template lands at ~1.0 (identical text, identical
/// tokenizer; only the join boundary differs). A dropping one lands at 0.0.
/// The dead zone between 0.25 and 0.75 is enormous on purpose: nothing lands
/// there by accident, so anything that does is reported inconclusive and
/// fails open rather than guessed at.
const double kSystemRoleDroppedRatio = 0.25;
const double kSystemRoleHonoredRatio = 0.75;

/// The calibration arm must actually move, or the server's `prompt_tokens`
/// are not a measurement at all (constant, block-rounded, padded). The filler
/// is ~200 words, so every real tokenizer clears this by 4x; a server that
/// doesn't is reported inconclusive instead of being handed a verdict derived
/// from a division by noise.
const int kSystemRoleProbeMinRefTokens = 50;

/// Bounded so an inconclusive probe can retry without ever becoming a
/// per-turn request. Spent WITHIN one [SystemRoleProbe.ensureProbed] call —
/// the model-ready transition that arms it fires once per load, so a budget
/// spread across calls would never be spendable at all. Reset (and refunded)
/// by [SystemRoleProbe.reset] on backend stop.
const int kSystemRoleProbeMaxAttempts = 3;

/// Gap before re-measuring after an inconclusive attempt, multiplied by the
/// attempt number: 3s, then 6s. Long enough that a backend still finishing
/// its warm-up has actually moved on by the retry, short enough that a
/// dropping model is fixed within ~10s of load — one or two replies, not a
/// whole session. Worst case for a permanently-silent server is three
/// `max_tokens: 1` requests spread over 9 seconds, and then silence.
const Duration kSystemRoleProbeRetryBackoff = Duration(seconds: 3);

/// Generous: this is one token of generation behind at most a ~300-token
/// prefill, but a cold model on a slow disk can still take a while to answer
/// its very first request. Because the arms short-circuit on the first
/// failure, a dead server costs exactly one of these, not three.
const Duration kSystemRoleProbeTimeout = Duration(seconds: 60);

/// Prepend [system] to the OpenAI chat user content, for backends whose
/// template silently discards the system role.
///
/// TRADE-OFF, stated plainly: on these backends the character card, the
/// persona and the scenario become text the model sees inside the user turn,
/// so it may read them as something the human typed. That is strictly better
/// than the alternative, which is not a cleaner prompt — it is NO character
/// card, NO persona, NO scenario and NO examples reaching the model at all. A
/// slightly mis-attributed character beats an absent one.
///
/// It is also why the app's own state blocks carry an attribution line in
/// their own words (prompt_injection/state_zone_frame.dart) rather than
/// relying on the system role to say who wrote them: the role is exactly what
/// these backends throw away, so a frame that leaned on it would be silently
/// gone on the models that need it most.
///
/// Handles both content shapes [GenerationParams.openAiUserContent] produces:
/// a plain string, or the multimodal part array used when images ride along
/// (the text goes into the first text part, so the image parts keep their
/// order and the payload stays valid).
Object foldSystemIntoUserContent(String system, Object userContent) {
  if (userContent is String) return '$system\n\n$userContent';
  if (userContent is List) {
    final parts = List<Object?>.from(userContent);
    for (var i = 0; i < parts.length; i++) {
      final part = parts[i];
      if (part is Map && part['type'] == 'text') {
        parts[i] = <String, Object>{
          ...part.cast<String, Object>(),
          'text': '$system\n\n${part['text'] ?? ''}',
        };
        return parts;
      }
    }
    return [
      <String, Object>{'type': 'text', 'text': system},
      ...parts,
    ];
  }
  return userContent;
}
