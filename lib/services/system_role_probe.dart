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

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Per-run memory of which backend identities actually DELIVER the leading
/// `system` message to the model — the system-role sibling of
/// [ToolTransportProbe] (services/chat/pass_support.dart).
///
/// ## The defect this exists for
///
/// The managed backend always launches with `--jinja` (kobold_service.dart),
/// which makes KoboldCpp run the GGUF's OWN embedded chat template instead of
/// its built-in AutoGuess string adapter. That is what lets `enable_thinking`
/// reach reasoning models — but a great many roleplay GGUFs ship a template
/// that simply has no branch for the system role. The canonical one,
/// intervitens-mini-magnum-12b-v1.1, ends its role loop with
/// `raise_exception('Only user and assistant roles are supported!')`.
///
/// KoboldCpp does not surface that. It answers HTTP 200 with a perfectly
/// plausible reply, and the entire system message is simply GONE. Measured on
/// the maintainer's own machine (KoboldCpp 1.117.1, same binary, same request,
/// a 266-token system block):
///
/// ```text
///   mini-magnum-12b   system message present -> prompt_tokens   7
///                     same text in the user  -> prompt_tokens 273
///   gemma-4-31B       system message present -> prompt_tokens 273
///                     same text in the user  -> prompt_tokens 270
/// ```
///
/// Front Porch AI puts the character card, the persona, the scenario and the
/// example dialogue in that message. So a user on such a model has been
/// chatting with no character at all — the model was answering as a blank
/// assistant and nobody could tell, because the reply always looked fine.
///
/// ## How the measurement works, and why it is shaped like this
///
/// The obvious A/B — "system present" vs "system absent" — is WRONG, and
/// wrong in the direction that silently undoes the fix for people it should
/// have left alone. Its delta is the sum of two independent effects: the
/// system text being discarded (the real defect) and the template ADDING
/// content because no system message was supplied. Only the first is a bug.
/// A template carrying
///
/// ```jinja
///   {%- if not system_message %}<a few hundred tokens of house rules>{%- endif %}
/// ```
///
/// makes the "absent" arm cost MORE all on its own — Cohere Command-R bakes
/// ~110 tokens this way, and several Llama-3 / Mistral roleplay conversions
/// copy the pattern. Verified against a loopback server that delivers every
/// byte of the system message but adds a 120-token default preamble when none
/// is sent: the old present-vs-absent A/B called that model "dropped" and
/// folded the card into the user turn on a backend that never needed it.
///
/// So the probe never removes the system message. Three `max_tokens: 1`
/// requests, each with a system message AND a user message present:
///
/// ```text
///   A  system: MARKER              user: PING            -> baseline
///   B  system: MARKER + FILLER     user: PING            -> filler in SYSTEM
///   C  system: MARKER              user: FILLER + PING   -> filler in USER
/// ```
///
/// `sysCost = B - A` is what the server charged for the filler when it rode
/// the system role. `refCost = C - A` is what the SAME filler costs through a
/// role we know is delivered — the calibration arm, which is why the probe
/// never has to guess the server's tokenizer. The verdict is the ratio:
///
/// ```text
///   sysCost / refCost >= 0.75 -> honored
///   sysCost / refCost <= 0.25 -> dropped
///   anything between          -> inconclusive, fail open
/// ```
///
/// Everything that is not the filler is byte-identical across the three arms
/// — same message count, same roles, same markers, same ping — so a baked-in
/// preamble (present in all three) and fixed per-request padding both cancel
/// in the differences, and a server whose `usage` is constant collapses
/// `refCost` to ~0 and trips the [kSystemRoleProbeMinRefTokens] floor instead
/// of being handed a confident verdict. A template that TRUNCATES rather than
/// drops lands at `sysCost ~ 0` too and is correctly called a drop: the
/// marker alone fills the kept window, so the card would be cut off just as
/// completely.
///
/// ## The verdict
///
/// Recorded once per backend+model identity and cached for the run. Identity
/// keys carry the backend name + model, so switching models re-probes by
/// construction (capability is per model, not per server).
///
/// ## When it runs
///
/// [ensureProbed] is armed from the backend's model-ready transition — never
/// from the generation path. Two reasons, and the second is the important
/// one: a probe on the generation path would ride every turn, and its
/// unrelated prompts would EVICT KoboldCpp's prefix cache for the live chat,
/// making the next reply a cold prefill. Right after load there is no chat
/// prompt cached yet, so it costs nothing but three `max_tokens: 1` requests.
///
/// The retry budget is spent INSIDE that one call, because model-ready fires
/// once per load: an earlier design that retried by being called AGAIN could
/// never retry at all, so one timeout at load left the identity unmeasured —
/// and every reply card-less — for the whole run, recoverable only by
/// restarting the backend, which nothing told the user to do. A single
/// [ensureProbed] therefore chains up to [kSystemRoleProbeMaxAttempts]
/// measurements spaced by [retryBackoff] and stops at the first one that
/// concludes.
///
/// Nothing ever waits on the verdict, so the first token is never held up.
/// Until it lands the backend behaves exactly as it does today; on a dropping
/// model that means the first reply or two after load is still card-less, and
/// every reply after that is fixed.
class SystemRoleProbe {
  SystemRoleProbe({this.retryBackoff = kSystemRoleProbeRetryBackoff});

  /// Wait before re-measuring after an inconclusive attempt, multiplied by
  /// the attempt number (so 3s, then 6s). A plain constructor argument rather
  /// than a test-only hook: the singleton takes the production default, and a
  /// test that has to exercise three attempts can ask for milliseconds
  /// instead of adding nine seconds to every run of the suite.
  final Duration retryBackoff;

  /// true = the system message reaches the model, false = silently dropped.
  final Map<String, bool> _verdicts = {};

  /// The live attempt-chain per identity, if one is running. Presence is the
  /// "never two probes at once" guard; the token itself is what lets [reset]
  /// disown a probe that is ALREADY on the wire without also disowning the
  /// fresh one that replaced it.
  final Map<String, _ProbeRun> _runs = {};

  /// Identities whose whole chain came back inconclusive. This is not the
  /// retry budget — that is a loop counter inside one [ensureProbed] call —
  /// it is only the "do not start the chain over" marker, and it is needed
  /// because the model-ready transition that arms the probe is driven by a
  /// REGEX over the backend's console output and can legitimately fire more
  /// than once for a single load. Without it, a permanently-silent server
  /// would be re-probed once per matching log line. Cleared by [reset].
  final Set<String> _exhausted = {};

  /// The app-wide default, so the provider graph does not have to construct
  /// and thread one for a single consumer. It has exactly one: KoboldService,
  /// via [KoboldSystemRole] — the payload builder in openai_chat_stream.dart
  /// is handed the resolved boolean as a parameter and never touches this
  /// class.
  ///
  /// Which is precisely why it is a DEFAULT and not the only way in:
  /// `KoboldService(storage, systemRoleProbe: …)` takes an override, and
  /// tests use it. A static verdict map shared between test cases is shared
  /// state, and shared state is where flakes come from.
  static final SystemRoleProbe instance = SystemRoleProbe();

  /// True only on hard evidence. Untested and honored both answer false, so
  /// every unknown backend keeps today's behaviour — the fold is applied ONLY
  /// where the drop was actually measured.
  ///
  /// This single bit is the whole production surface. Deliberately NOT the
  /// three-state enum its sibling [ToolTransportProbe] exposes: that probe's
  /// third state is genuinely consumed (tool_support_tester.dart re-arms on
  /// `untested`), this one's was not, and an unused enum is just a thing to
  /// keep in sync.
  bool isSystemDropped(String backendIdentity) =>
      _verdicts[backendIdentity] == false;

  /// Three-state view for guards: null = never measured, true = honored,
  /// false = dropped. Tests need to tell "measured healthy" from "never
  /// measured" — that difference is exactly "the fix works" vs "the probe
  /// silently did not run" — and [isSystemDropped] flattens both to false.
  @visibleForTesting
  bool? verdictFor(String backendIdentity) => _verdicts[backendIdentity];

  /// Forget everything about an identity — settled verdict, spent budget, and
  /// any measurement still in flight. Called by the backend when it stops, so
  /// a GGUF swapped in at the same path is never judged by the previous
  /// file's template.
  ///
  /// Cancelling the in-flight run is the load-bearing half, and it is two
  /// fixes. A probe measuring the OLD server must not land its verdict after
  /// the reset meant to forget it — that template may not even be loaded any
  /// more — so the run is disowned and drops its result. And its socket is
  /// closed rather than left to time out: every arm holds the local engine's
  /// only request slot, so without the close the fresh probe AND the user's
  /// first message queue behind a request to a server that is already gone,
  /// for up to [kSystemRoleProbeTimeout].
  void reset(String backendIdentity) {
    _runs.remove(backendIdentity)?.cancel();
    _exhausted.remove(backendIdentity);
    _verdicts.remove(backendIdentity);
  }

  /// Measure whether [baseUrl] delivers the system message, once per
  /// [identity]. Idempotent and safe to call from anywhere; returns
  /// immediately when a verdict already exists, a chain is already running,
  /// or the retry budget for that identity is spent.
  ///
  /// [runExclusive] lets the caller serialize each request against a
  /// single-slot local engine. KoboldService passes its own request-slot
  /// wrapper, so EVERY arm both waits for any in-flight generation and
  /// occupies the shared slot while it runs — a probe arm can no longer race
  /// the user's own turn, and evals that `waitForIdle` genuinely wait for it.
  /// Per arm rather than around the whole probe on purpose: it caps how long
  /// anything can be stuck behind the probe at one request, and it leaves the
  /// slot free during the retry backoff.
  ///
  /// Fails OPEN by design: anything unexpected (non-200, no `usage`, socket
  /// error, timeout, an ambiguous ratio) leaves the identity untested, which
  /// means the system message keeps being sent exactly as it is today. A
  /// broken probe must never degrade a backend that was working.
  Future<void> ensureProbed({
    required String baseUrl,
    required String identity,
    Future<int?> Function(Future<int?> Function() body)? runExclusive,
    void Function(String message)? log,
  }) async {
    if (identity.isEmpty ||
        _verdicts.containsKey(identity) ||
        _exhausted.contains(identity) ||
        _runs.containsKey(identity)) {
      return;
    }
    final run = _ProbeRun();
    _runs[identity] = run;
    try {
      Future<int?> arm(String system, String user) {
        Future<int?> body() => _promptTokens(baseUrl, run, system, user);
        return runExclusive == null ? body() : runExclusive(body);
      }

      for (var attempt = 1; attempt <= kSystemRoleProbeMaxAttempts; attempt++) {
        if (attempt > 1) {
          // Backoff outside the engine slot: a server that is still settling
          // needs time, and nothing should be queued behind us while we wait.
          await Future<void>.delayed(retryBackoff * (attempt - 1));
          if (run.cancelled) return;
        }
        final verdict = await _measure(identity, attempt, arm);
        // Disowned mid-flight (the backend stopped, the model changed): this
        // number describes a template that may no longer be loaded. Drop it.
        if (run.cancelled) return;
        if (verdict == null) continue;
        _verdicts[identity] = verdict;
        if (!verdict) {
          log?.call(
            "This model's chat template throws system messages away, so the "
            'character card was never reaching the model. Front Porch AI is '
            'now sending the card inside the message instead, which fixes it.',
          );
        }
        return;
      }
      _exhausted.add(identity);
      debugPrint(
        '[SystemRole] Giving up on $identity after '
        '$kSystemRoleProbeMaxAttempts inconclusive attempts — the system '
        'message keeps being sent exactly as it is now. Restarting the '
        'backend measures it again.',
      );
    } finally {
      // Only if the run is still OURS: [reset] may have replaced it with a
      // fresh chain while this one was unwinding.
      if (identical(_runs[identity], run)) _runs.remove(identity);
    }
  }

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

  @visibleForTesting
  void resetForTest() {
    for (final run in _runs.values) {
      run.cancel();
    }
    _runs.clear();
    _verdicts.clear();
    _exhausted.clear();
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
