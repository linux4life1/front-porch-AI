// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Software Foundation, either version 3 of the License, or
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

import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/models/chat_message.dart';
import 'package:front_porch_ai/models/group_chat.dart';
import 'package:front_porch_ai/models/needs_impact.dart';
import 'package:front_porch_ai/services/chat/needs_simulation.dart';
import 'package:front_porch_ai/services/chat/realism_verification.dart';

/// Plain leaf for needs impact.
///
/// Model provides net signed deltas for the scene (open prompt, like bond/emotion evals).
/// Optional Director/Verifier corrects when authority is enabled on the card.
/// Simple clamps only. Decay is handled separately in NeedsSimulation.
class NeedsImpactEvaluator {
  final Future<String?> Function(
    String responseText, {
    void Function(String)? onChunk,
    int strength,
    String? userCritique,
    Map<String, int>? previousDeltas,
    Map<String, int>? currentNeeds,
    int? decayTurns,
  })
  evaluateNeedsImpactCall;
  final Future<VerificationResult> Function({
    required String evalKind,
    required String rawOutput,
    required String sceneResponse,
    Map<String, dynamic>? preState,
    CharacterCard? activeChar,
    GroupChat? activeGroup,
    List<ChatMessage>? recentMessages,
    String? promptText,
    Map<String, String>? injections,
    int? strictnessOverride,
    int? maxPassesOverride,
  })?
  verifyRealismOutput;

  final Future<String?> Function(
    String prompt, {
    void Function(String)? onChunk,
  })?
  fireLLMEval;

  final Map<String, dynamic> Function()? getPendingRealismMetadata;
  final void Function(Map<String, dynamic>)? setPendingRealismMetadata;

  final void Function(int crashTurns)? onClimax;

  final CharacterCard? Function() getActiveCharacter;
  final GroupChat? Function() getActiveGroup;
  final bool Function() getIsObserverMode;
  final String Function() getCurrentSpeakerIdForRealism;
  final bool Function() getIsGroupNonObserverMode;
  final Map<String, int> Function(String charId) getGroupNeeds;
  final void Function(String charId, Map<String, int> needs) setGroupNeeds;
  final List<CharacterCard> Function() getGroupCharacters;
  final String Function(CharacterCard) getCharacterIdFromCard;
  final List<ChatMessage> Function() getMessages;

  final NeedsSimulation needsSimulation;

  final bool Function() getNeedsSimEnabled;
  final bool Function() getRealismEnabled;
  final bool Function() getNeedsModelAuthorityEnabled;
  final int Function() getNeedsSimStrength;

  NeedsImpactEvaluator({
    required this.evaluateNeedsImpactCall,
    this.verifyRealismOutput,
    this.fireLLMEval,
    this.getPendingRealismMetadata,
    this.setPendingRealismMetadata,
    required this.getActiveCharacter,
    required this.getActiveGroup,
    required this.getIsObserverMode,
    required this.getCurrentSpeakerIdForRealism,
    required this.getIsGroupNonObserverMode,
    required this.getGroupNeeds,
    required this.setGroupNeeds,
    required this.getGroupCharacters,
    required this.getCharacterIdFromCard,
    required this.getMessages,
    required this.needsSimulation,
    required this.getNeedsSimEnabled,
    required this.getRealismEnabled,
    required this.getNeedsModelAuthorityEnabled,
    this.getNeedsSimStrength = _defaultStrength,
    this.onClimax,
  });

  static int _defaultStrength() => 1;

  /// Simple keyword-based fallback for scenes where the model returns
  /// all-zero or empty deltas. Scans for activity keywords and assigns
  /// reasonable positive deltas so the character doesn't stagnate.
  static Map<String, int> afkKeywordFallback(String sceneText) {
    final text = sceneText.toLowerCase();
    final result = <String, int>{};

    bool matchesWordBoundary(Iterable<String> keywords, String text) {
      return keywords.any((k) {
        return RegExp('\\b${RegExp.escape(k)}\\b').hasMatch(text);
      });
    }

    void check(Iterable<String> keywords, Map<String, int> deltas) {
      if (matchesWordBoundary(keywords, text)) {
        for (final entry in deltas.entries) {
          final existing = result[entry.key] ?? 0;
          if (entry.value > existing) {
            result[entry.key] = entry.value;
          }
        }
      }
    }

    // Bladder
    check([
      'toilet', 'bathroom', 'urinate', 'peed', 'peeing',
      'used the bathroom', 'went to the bathroom', 'en suite',
    ], {'bladder': 50});

    // Hygiene — specific phrases first
    check([
      'shower', 'showering', 'showered', 'showers',
      'bath', 'bathed', 'bathing',
    ], {'hygiene': 40, 'comfort': 10});
    check([
      'washed her face', 'washed up', 'washed herself', 'dish',
      'brushed her teeth', 'brushing her teeth',
    ], {'hygiene': 20});
    check([
      'splashed water on her face', 'splashed some water',
      'freshened up', 'freshening up',
    ], {'hygiene': 15});
    check(['washed', 'washing'], {'hygiene': 25});
    check([
      'changed clothes', 'changed into', 'got dressed',
      'pajamas', 'clean clothes', 'comfy clothes',
    ], {'hygiene': 10});

    // Hunger
    check([
      'ate', 'eating', 'had breakfast', 'had lunch', 'had dinner', 'dinner',
      'made breakfast', 'made lunch', 'made dinner',
    ], {'hunger': 35});
    check([
      'food', 'foods', 'meal', 'pizza', 'leftovers', 'leftover', 'pasta',
      'sandwich', 'snack', 'popcorn', 'cereal', 'apple', 'cheese', 'toast',
      'cooking', 'browsing recipes', 'recipe', 'groceries', 'takeout',
    ], {'hunger': 25});
    check([
      'fridge', 'refrigerator', 'microwave', 'kitchen',
      'making food', 'preparing food',
    ], {'hunger': 10});

    // Beverages → energy (not hunger)
    check([
      'coffee', 'tea', 'orange juice', 'juice', 'water', 'soda',
      'beverage', 'mug', 'cup of', 'fresh pot', 'brew',
    ], {'energy': 7});

    // Energy
    check([
      'slept', 'sleeping', 'asleep', 'fell asleep', 'went to sleep', 'sleep',
    ], {'energy': 50});
    check([
      'nap', 'napping', 'dozed', 'dozing', 'dozed off', 'drifted off',
    ], {'energy': 25});
    check([
      'rested', 'resting', 'lay down', 'lying down',
      'stretched out', 'curled up', 'lounging',
    ], {'energy': 15});
    check([
      'stretch', 'stretching', 'yawned', 'yawning',
    ], {'energy': 5});

    // Comfort
    check([
      'book', 'books', 'reading', 'reads', 'read a', 'novel', 'magazine',
      'page', 'chapter', 'story',
    ], {'comfort': 20});
    check([
      'tv', 'television', 'movie', 'show', 'shows', 'watching',
      'video', 'netflix', 'streaming',
    ], {'comfort': 10});
    check([
      'photo', 'album', 'memento', 'photograph',
      'pictures', 'memories', 'scrapbook',
    ], {'comfort': 15});
    check([
      'couch', 'sofa', 'bed', 'comfortable', 'cozy', 'warm',
      'peaceful', 'relaxed', 'content', 'serene',
    ], {'comfort': 10});
    check([
      'sunlight', 'morning sun', 'golden light', 'dappled',
      'nice view', 'backyard', 'birds singing', 'garden',
    ], {'comfort': 8});
    check([
      'candle', 'music', 'quiet', 'rain', 'fireplace',
      'calm', 'tranquil',
    ], {'comfort': 10});

    // Fun
    check([
      'phone', 'computer', 'laptop', 'social media',
      'scrolling', 'instagram', 'facebook', 'browsing',
      'online', 'website', 'surfing',
    ], {'fun': 8});
    check([
      'game', 'gaming', 'played', 'hobby', 'craft',
      'drawing', 'music', 'instrument',
    ], {'fun': 15});

    // Social
    check([
      'friend', 'friends', 'neighbor', 'neighbors',
      'talked to', 'chatting with', 'texted', 'called',
      'phone call', 'messaged',
    ], {'social': 15});

    return result;
  }

  Future<void> evaluateAndApply(String responseText, {bool isAfk = false}) async {
    if (!getNeedsSimEnabled() ||
        !getRealismEnabled() ||
        responseText.trim().isEmpty) {
      return;
    }
    final char = getActiveCharacter();
    if (char == null && getActiveGroup() == null) return;

    final strength = getNeedsSimStrength();
    try {
      // Check metadata for AFK needs context (set by _runPostGenNeedsChecks)
      final meta = getPendingRealismMetadata?.call();
      final afkNeeds = meta?['_afk_needs_vector'] as Map<String, int>?;
      final afkDecayTurns = meta?['_afk_decay_turns'] as int?;
      // Clean up immediately so it doesn't leak into message metadata
      if (meta != null) {
        meta.remove('_afk_needs_vector');
        meta.remove('_afk_decay_turns');
      }

      final text = await evaluateNeedsImpactCall(
        responseText,
        strength: strength,
        currentNeeds: afkNeeds,
        decayTurns: afkDecayTurns,
      );
      if (text == null) return;

      String effectiveText = text;
      final authority = getNeedsModelAuthorityEnabled();
      final cardVerifEnabled =
          getActiveCharacter()
              ?.frontPorchExtensions
              ?.realismVerificationEnabled ??
          false;
      if (verifyRealismOutput != null && authority && cardVerifEnabled) {
        // Director authority + card verif on: review loop corrections have authority on deltas (simple model + director; stronger critique changes applied via effective).
        // Skip verify cb entirely if card verif flag false (even under authority) to avoid unnecessary fire + metadata attempt (leaf would early-accept anyway).
        try {
          final vres = await verifyRealismOutput!(
            evalKind: 'needs_impact',
            rawOutput: text,
            sceneResponse: responseText,
            // Pass a needs snapshot shape consistent with what _captureRealismState
            // embeds in realism_state['needs'] (and what timeline/restore paths expect).
            // At this point in evaluateAndApply the sim.vector is still the pre-impact one.
            preState: {
              'needs': {'vector': needsSimulation.vector},
            },
            activeChar: getActiveCharacter(),
            activeGroup: getActiveGroup(),
            recentMessages: getMessages(),
            promptText:
                'needs impact (straight deltas; Director authority on corrections; user-requested strength ' +
                strength.toString() +
                'x — emit/correct deltas at this magnitude)',
            injections: const {},
          );
          if (vres.correctedRaw != null && vres.correctedRaw!.isNotEmpty) {
            effectiveText = vres.correctedRaw!;
          }
          if (vres.status.isNotEmpty) {
            final current =
                (getPendingRealismMetadata?.call() ?? <String, dynamic>{});
            current[RealismVerification.kMetaKey] = vres.toMetadata();
            setPendingRealismMetadata?.call(current);
            debugPrint(
              '[Realism:Verifier] Needs impact verified (authority) status=${vres.status} passes=${vres.passes}',
            );
          }
        } catch (e) {
          debugPrint('[Realism:Verifier] Needs wrap error (passthrough): $e');
          // Passthrough on error (consistent); no metadata for failure (chips fall back to model deltas).
        }
      }
      // else: straight model deltas (authority off, or verif card flag off, or no verify cb). No redundant else if.

      // Parse deltas directly from effective (model or Director corrected).
      // Robust JSON attempt first, then regex fallback.
      debugPrint(
        '[Realism:Needs] Raw evaluator response: '
        '${effectiveText.substring(0, effectiveText.length > 300 ? 300 : effectiveText.length)}',
      );
      final deltas = <String, int>{};
      Map<String, dynamic> parsed = {};
      try {
        final noFence = effectiveText
            .replaceAll(RegExp(r'```(?:json)?\s*|\s*```', dotAll: true), ' ')
            .trim();
        final si = noFence.indexOf('{');
        final ei = noFence.lastIndexOf('}');
        if (si >= 0 && ei > si) {
          final obj = jsonDecode(noFence.substring(si, ei + 1));
          if (obj is Map<String, dynamic>) parsed = obj;
        }
      } catch (_) {
        parsed = {};
      }
      for (final k in NeedsSimulation.needKeys) {
        int? d;
        if (parsed.isNotEmpty) {
          final v = parsed['${k}_delta'] ?? parsed[k];
          if (v is num) d = v.toInt();
        }
        d ??=
            _extractInt(effectiveText, '${k}_delta') ??
            _extractInt(effectiveText, k);
        if (d != null) {
          deltas[k] = d;
        }
      }

      // Simple clamps only (no complex gates/rules). Prevent obviously broken output from the model.
      // The Director (when authority + verification enabled) does the scene-faithfulness check,
      // just like bond/emotion/relationship evals. Strength scaling is already instructed in the prompt.
      //
      // Positive side loosened to +100 so a strong replenishing scene (meal, long rest, thorough
      // care/bathing, deep social connection) can meaningfully restore a need in one go.
      // Negative side kept at -30 to avoid any single scene catastrophically tanking a need.
      for (final k in deltas.keys.toList()) {
        deltas[k] = deltas[k]!.clamp(-30, 100);
      }

      // AFK zero-floor: model sometimes ignores "Only report positive gains"
      // and emits small negative deltas. Zero them to match the instruction.
      if (isAfk) {
        for (final k in deltas.keys.toList()) {
          if (deltas[k]! < 0) deltas[k] = 0;
        }
      }

      // ── AFK keyword merge: fills any need that the model left at zero
      // or didn't include, without overwriting the model's non-zero deltas.
      // This handles both the all-zero case and the partial-miss case where
      // the model got some needs right but ignored obvious activities.
      if (isAfk) {
        final fallback = afkKeywordFallback(responseText);
        if (fallback.isNotEmpty) {
          bool filled = false;
          for (final k in NeedsSimulation.needKeys) {
            if ((deltas[k] == null || deltas[k] == 0) && (fallback[k] != null && fallback[k]! > 0)) {
              deltas[k] = fallback[k]!;
              filled = true;
            }
          }
          if (filled) {
            debugPrint(
              '[Realism:Needs] AFK keyword merge filled gaps: $fallback',
            );
          }
        }
      }

      // Strength (1-5x) is communicated to the model on the first needs-impact call and (when
      // Director authority is enabled) to the verifier critique so both emit/correct at the
      // user-requested magnitude in a single pass. We do NOT post-multiply here — that would
      // cause the Director to take an already-scaled delta (e.g. -15 at 5x) and multiply it
      // again (→ -75). The numbers that come back from the (Director-corrected) effective text
      // are the final deltas to apply. (See user clarification 2026-06: multiplier is applied
      // at first run / in the prompt to model+Director; Director must not re-scale the scaled value.)
      // If the model ignores the scale instruction the deltas will simply be smaller than desired
      // (model compliance issue, not a post-hoc multiplication).

      final reasonMatch = RegExp(
        r'"reason"\s*:\s*"([^"]*)"',
      ).firstMatch(effectiveText);
      final reason = reasonMatch?.group(1)?.trim();

      bool isClimax = false;
      int crashTurns = 5;
      if (parsed.isNotEmpty) {
        final c = parsed['is_climax'];
        if (c is bool) {
          isClimax = c;
        } else if (c is String) {
          isClimax = c.toLowerCase() == 'true';
        }

        final t = parsed['crashTurns'] ?? parsed['refractory_turns'];
        if (t is num) crashTurns = t.toInt();
      } else {
        final re = RegExp(r'"is_climax"\s*:\s*(true|false)');
        final m = re.firstMatch(effectiveText);
        if (m != null) isClimax = m.group(1) == 'true';
        crashTurns =
            _extractInt(effectiveText, 'crashTurns') ??
            _extractInt(effectiveText, 'refractory_turns') ??
            5;
      }

      if (isClimax) {
        onClimax?.call(crashTurns.clamp(1, 10));
      }

      final impact = NeedsImpact(
        deltas: deltas,
        reason: (reason != null && reason.toLowerCase() != 'none')
            ? reason
            : null,
      );

      needsSimulation.applySceneImpact(impact);
      debugPrint(
        '[Realism:Needs] Applied deltas: $deltas (reason: $reason) '
        'strength=$strength textLen=${responseText.length}',
      );
    } catch (e) {
      debugPrint('[Realism:Needs] evaluateAndApply error: $e');
    }
  }

  int? _extractInt(String text, String key) {
    final re = RegExp('"$key"\\s*:\\s*(-?\\d+)');
    final m = re.firstMatch(text);
    if (m != null) return int.tryParse(m.group(1)!);
    return null;
  }

  Future<bool> reprocessWithUserCritique(
    String responseText,
    Map<String, int> oldDeltas,
    String critique,
  ) async {
    // Use the injected evaluateNeedsImpactCall (now supports critique/oldDeltas for unified rich prompt + personality/stance/recent/full guidance + MUST + examples).
    final strength = getNeedsSimStrength();

    try {
      // No debugPrint here — the engine logs the same "Running manual
      // reprocess impact eval" line itself; printing in both places made one
      // eval read as a double-fire in the console.
      String? text = await evaluateNeedsImpactCall(
        responseText,
        strength: strength,
        userCritique: critique,
        previousDeltas: oldDeltas,
      );

      // C: bounded retry on empty/fragile (one extra attempt with emphasis)
      if (text == null || text.trim().isEmpty) {
        debugPrint(
          '[Realism:Needs] reprocess empty response, retrying once...',
        );
        text = await evaluateNeedsImpactCall(
          responseText,
          strength: strength,
          userCritique:
              '$critique Output ONLY the flat JSON now with all seven _delta keys.',
          previousDeltas: oldDeltas,
        );
      }

      if (text == null || text.trim().isEmpty) return false;

      String effectiveText = text; // already stripped by evaluate path

      final deltas = <String, int>{};
      Map<String, dynamic> parsed = {};
      try {
        final noFence = effectiveText
            .replaceAll(RegExp(r'```(?:json)?\s*|\s*```', dotAll: true), ' ')
            .trim();
        final si = noFence.indexOf('{');
        final ei = noFence.lastIndexOf('}');
        if (si >= 0 && ei > si) {
          final obj = jsonDecode(noFence.substring(si, ei + 1));
          if (obj is Map<String, dynamic>) parsed = obj;
        }
      } catch (_) {
        parsed = {};
      }
      for (final k in NeedsSimulation.needKeys) {
        int? d;
        if (parsed.isNotEmpty) {
          final v = parsed['${k}_delta'] ?? parsed[k];
          if (v is num) d = v.toInt();
        }
        d ??=
            _extractInt(effectiveText, '${k}_delta') ??
            _extractInt(effectiveText, k);
        if (d != null) {
          deltas[k] = d;
        }
      }

      // C: if after strip/parse we got literally no delta keys at all, treat as failure (do not apply empty "correction")
      if (deltas.isEmpty) {
        debugPrint(
          '[Realism:Needs] reprocess parsed no deltas; treating as failure',
        );
        return false;
      }

      for (final k in deltas.keys.toList()) {
        deltas[k] = deltas[k]!.clamp(-30, 100);
      }

      final reasonMatch = RegExp(
        r'"reason"\s*:\s*"([^"]*)"',
      ).firstMatch(effectiveText);
      final reason = reasonMatch?.group(1)?.trim();

      bool isClimax = false;
      int crashTurns = 5;
      if (parsed.isNotEmpty) {
        final c = parsed['is_climax'];
        if (c is bool) {
          isClimax = c;
        } else if (c is String) {
          isClimax = c.toLowerCase() == 'true';
        }
        final t = parsed['crashTurns'] ?? parsed['refractory_turns'];
        if (t is num) crashTurns = t.toInt();
      } else {
        final re = RegExp(r'"is_climax"\s*:\s*(true|false)');
        final m = re.firstMatch(effectiveText);
        if (m != null) isClimax = m.group(1) == 'true';
        crashTurns =
            _extractInt(effectiveText, 'crashTurns') ??
            _extractInt(effectiveText, 'refractory_turns') ??
            5;
      }

      if (isClimax) {
        onClimax?.call(crashTurns.clamp(1, 10));
      }

      final impact = NeedsImpact(
        deltas: deltas,
        reason: (reason != null && reason.toLowerCase() != 'none')
            ? reason
            : null,
      );

      needsSimulation.applySceneImpact(impact);

      // Store the metadata for the update
      final currentMeta =
          (getPendingRealismMetadata?.call() ?? <String, dynamic>{});
      // We manually construct a fake VerificationResult metadata to display the Director Corrected pill.
      currentMeta[RealismVerification.kMetaKey] = {
        'status': 'Director corrected (manual)',
        'passes': 1,
      };
      setPendingRealismMetadata?.call(currentMeta);

      return true;
    } catch (e) {
      debugPrint('[Realism:Needs] reprocessWithUserCritique error: $e');
      return false;
    }
  }
}
