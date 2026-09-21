// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// With you / Away glance. Own post-reply pass. NEVER writes spatial stance.

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/services/chat/realism_tools.dart';

/// Yes/no: are they physically with {{user}} right now?
///
/// WHY IT IS NOT THE POSTURE PASS. Posture writes `spatialStance` and is
/// what stops characters teleporting ("don't jump locations"). Asking
/// "are you with the user" in that same breath makes the model answer
/// *place* in terms of *proximity*. This leaf only flips the glance word.
/// It reads the stance that posture already wrote. It never calls
/// [RelationshipService.setSpatialStance].
///
/// Fail closed: missing or unparseable → null → caller leaves the last
/// bit (or the keyword fallback) alone.
class WithUserEval {
  final Future<String?> Function({
    required String debugLabel,
    required List<Map<String, dynamic>> tools,
    required String Function({required bool toolsMode}) buildPrompt,
  })
  fire;

  const WithUserEval({required this.fire});

  static const kWithUserTool = kWithUserToolName;
  static List<Map<String, dynamic>> get tools => kWithUserEvalTools;

  /// Stance is CONTEXT only — "where they already are", not a request to
  /// move them. Phone / their own place / next room = false.
  static String rubric(String charName, String userName) =>
      'WITH USER — "with_user": true ONLY when $charName and $userName are '
      'physically in the same place right now, close enough to share a scene '
      '(same room, same car, walking together, sitting together). '
      'False when $charName is at their own home, at work, in another room, '
      'elsewhere in town, or only talking by phone / text / video. '
      'Same city is not enough. Do not move anyone — only report whether '
      'they are together.\\n\\n';

  static String buildPrompt({
    required String charName,
    required String userName,
    required String reply,
    required String recentExchange,
    required String stance,
    required bool toolsMode,
    bool quiet = false,
  }) {
    final stanceLine = stance.trim().isEmpty
        ? ''
        : 'Last known position of $charName (do not change this, only use it): '
              '"$stance".\\n\\n';
    final sceneLabel = quiet
        ? 'The current scene (they have not spoken this turn)'
        : 'The reply that just happened';
    final sceneBody = quiet
        ? (recentExchange.trim().isEmpty ? '(stance only)' : recentExchange)
        : reply;
    final recentBlock = quiet || recentExchange.trim().isEmpty
        ? ''
        : 'Recent exchange for context:\\n$recentExchange\\n\\n';
    return 'Read the scene below and answer one yes/no about $charName.\\n\\n'
        '${rubric(charName, userName)}'
        '$stanceLine'
        '$sceneLabel:\\n$sceneBody\\n\\n'
        '$recentBlock'
        '${toolsMode ? 'Report by calling the $kWithUserTool tool with "with_user". Use ONLY the tool — no plain-text reply.' : 'Respond with ONLY a flat JSON object containing "with_user" as true or false. '
                  'Do NOT use markdown code blocks — raw JSON only.\\n'
                  'Example: {"with_user": true} or {"with_user": false}'}';
  }

  /// null = do not touch the stored bit.
  static bool? parseWithUser(String? raw) {
    if (raw == null) return null;
    final m = RegExp(
      r'"with_user"\s*:\s*"?(true|false)"?',
      caseSensitive: false,
    ).firstMatch(raw);
    if (m == null) return null;
    return m.group(1)!.toLowerCase() == 'true';
  }

  Future<bool?> detect({
    required String charName,
    required String userName,
    required String reply,
    String recentExchange = '',
    String stance = '',
  }) async {
    if (reply.trim().isEmpty) return null;
    try {
      return parseWithUser(
        await fire(
          debugLabel: 'with_user',
          tools: tools,
          buildPrompt: ({required bool toolsMode}) => buildPrompt(
            charName: charName,
            userName: userName,
            reply: reply,
            recentExchange: recentExchange,
            stance: stance,
            toolsMode: toolsMode,
          ),
        ),
      );
    } catch (e) {
      debugPrint('[Presence] with_user check failed, glance unchanged: $e');
      return null;
    }
  }

  /// Quiet Away pulse: no new bubble. Stance + recent exchange only.
  /// null = leave the stored bit alone. Never writes spatial stance.
  Future<bool?> detectQuiet({
    required String charName,
    required String userName,
    String recentExchange = '',
    String stance = '',
  }) async {
    if (recentExchange.trim().isEmpty && stance.trim().isEmpty) return null;
    try {
      return parseWithUser(
        await fire(
          debugLabel: 'with_user_quiet',
          tools: tools,
          buildPrompt: ({required bool toolsMode}) => buildPrompt(
            charName: charName,
            userName: userName,
            reply: '',
            recentExchange: recentExchange,
            stance: stance,
            toolsMode: toolsMode,
            quiet: true,
          ),
        ),
      );
    } catch (e) {
      debugPrint('[Presence] away-pulse failed, glance unchanged: $e');
      return null;
    }
  }
}
