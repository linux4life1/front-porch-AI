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

import 'package:front_porch_ai/services/chat/chat.dart'
    show
        kFeelingsUnscoredLabel,
        kFeelingsUnscoredMeta,
        kFeelingsUnscoredTip,
        kNeedsUnaffectedMeta,
        RealismVerification;
import 'package:front_porch_ai/services/services.dart';

/// Extract the per-message Realism chip deltas from a message's active-swipe
/// metadata (the same keys the desktop bubble reads). Bond and trust keep
/// a recorded 0. Arousal still omits zero. A missing key stays omitted.
Map<String, dynamic>? webMessageChips(
  ChatService chat,
  Map<String, dynamic>? md,
  int index,
) {
  if (md == null) return null;
  final out = <String, dynamic>{};
  for (final entry in const {
    'bond_delta': 'bondDelta',
    'trust_delta': 'trustDelta',
  }.entries) {
    final v = md[entry.key];
    if (v is int) out[entry.value] = v;
  }
  final arousal = md['arousal_delta'];
  if (arousal is int && arousal != 0) out['arousalDelta'] = arousal;
  // A scored reply with no stored bond/trust is a dropped zero. The
  // bubble says "unchanged" instead of looking like the judge never ran.
  // Same list as the desktop bubble's realismTouched: the clock is not on
  // it, since Passage of Time runs with the engine off.
  final needs = md['needs_deltas'];
  final verif = md[RealismVerification.kMetaKey];
  final verifStatus = verif is Map && verif['status'] is String
      ? (verif['status'] as String).trim()
      : '';
  final scored =
      (md['emotion_label'] is String &&
          (md['emotion_label'] as String).isNotEmpty) ||
      (needs is Map && needs.isNotEmpty) ||
      md[kNeedsUnaffectedMeta] == true ||
      verifStatus.isNotEmpty;
  // The judge ran and could not be read: one "not scored" chip, never a
  // made-up "unchanged". Same rule as the desktop bubble.
  final unscored =
      md[kFeelingsUnscoredMeta] == true &&
      !out.containsKey('bondDelta') &&
      !out.containsKey('trustDelta');
  if (unscored) {
    out['feelingsUnscored'] = true;
    out['feelingsUnscoredLabel'] = kFeelingsUnscoredLabel;
    out['feelingsUnscoredTip'] = kFeelingsUnscoredTip;
  } else if (scored) {
    out.putIfAbsent('bondDelta', () => 0);
    out.putIfAbsent('trustDelta', () => 0);
  }
  for (final entry in const {
    'emotion_label': 'emotionLabel',
    'bond_reason': 'bondReason',
    'trust_reason': 'trustReason',
    'time_skip_to': 'timeSkipTo',
    'time_passed': 'timePassed',
    'chance_time_event': 'chanceTimeEvent',
  }.entries) {
    final v = md[entry.key];
    if (v is String && v.isNotEmpty) out[entry.value] = v;
  }
  if (needs is Map) {
    final nz = <String, dynamic>{};
    needs.forEach((k, v) {
      // NeedsSimulation.computeNeedsDeltasWithReasons stores {delta, reason}
      // per need; tolerate a plain int too. Carry BOTH the signed delta and
      // the reason so the web chip can show the same hover explanation the
      // desktop bubble does. (Map-not-int is why needs chips never rendered
      // on the web before — see the chip parser fix.)
      final delta = v is int
          ? v
          : (v is Map && v['delta'] is int ? v['delta'] as int : 0);
      if (delta == 0) return;
      final reason = (v is Map && v['reason'] is String)
          ? (v['reason'] as String)
          : '';
      nz[k.toString()] = {'delta': delta, 'reason': reason};
    });
    if (nz.isNotEmpty) out['needsDeltas'] = nz;
  }
  // Director-redo affordances (mirrors message_bubble.dart): the message can
  // be reprocessed when the service resolver is non-null (Needs on, at
  // least one need enabled, group speaker resolved). The client still
  // gates the button on last + not generating.
  final target = chat.reprocessNeedsTargetFor(index);
  if (target != null) {
    out['needsReprocessable'] = true;
    out['enabledNeeds'] = target.enabled;
    out['needsSpeaker'] = target.speaker;
  }
  // The other Manual Reprocess choice: score the reply's feelings again.
  final feelingsSpeaker = chat.reprocessFeelingsTargetFor(index);
  if (feelingsSpeaker != null) {
    out['feelingsReprocessable'] = true;
    out['feelingsSpeaker'] = feelingsSpeaker;
  }
  if (chat.needsActive && md['needs_deltas_pre_reprocess'] is Map) {
    out['needsRevertable'] = true;
  }
  if (md[kNeedsUnaffectedMeta] == true) out['needsUnaffected'] = true;
  final search = md['search_receipt'];
  if (search is Map) {
    final q = (search['query'] as String?)?.trim() ?? '';
    if (q.isNotEmpty) {
      out['searchQuery'] = q;
      out['searchOk'] = search['ok'] == true;
    }
  }
  final wiki = md['wiki_receipt'];
  if (wiki is Map) {
    final q = (wiki['query'] as String?)?.trim() ?? '';
    final webQuery = (out['searchQuery'] as String?) ?? '';
    if (q.isNotEmpty && q != webQuery) {
      out['wikiQuery'] = q;
      out['wikiOk'] = wiki['ok'] == true;
    }
  }
  // Director verifier chip, same fields the desktop bubble reads.
  if (verif is Map && verifStatus.isNotEmpty) {
    out['directorStatus'] = verifStatus;
    final passes = verif['passes'];
    out['directorPasses'] = passes is num ? passes.toInt() : 0;
    final reason = verif['reason'];
    if (reason is String && reason.trim().isNotEmpty) {
      out['directorReason'] = reason.trim();
    }
  }
  // Pockets & Wardrobe receipts. Pockets runs with Realism off, so these can
  // be the only chips on a reply.
  final pocketChanges = md['pocket_changes'];
  if (pocketChanges is List) {
    final receipts = [
      for (final raw in pocketChanges)
        if (raw is String && raw.trim().isNotEmpty) raw.trim(),
    ];
    if (receipts.isNotEmpty) out['pocketChanges'] = receipts;
  }
  final toolReceipt = md['tool_receipt'];
  if (toolReceipt is Map) {
    final tool = (toolReceipt['tool'] as String?)?.trim() ?? '';
    if (tool.isNotEmpty) {
      out['toolName'] = tool;
      out['toolOk'] = toolReceipt['ok'] == true;
      // Older phone bundles read mcpTool; keep the keys until they age out.
      out['mcpTool'] = tool;
      out['mcpOk'] = toolReceipt['ok'] == true;
    }
  }
  return out.isEmpty ? null : out;
}
