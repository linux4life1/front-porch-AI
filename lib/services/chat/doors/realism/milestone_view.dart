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

import 'package:front_porch_ai/database/database.dart'
    show GrowthMomentData, GrowthRingData;
import 'package:front_porch_ai/services/chat/growth_boons_bogies.dart';
import 'package:front_porch_ai/services/chat/growth_milestones.dart';
import 'package:front_porch_ai/services/chat/growth_store.dart';

/// Every word the milestone card and a Moments row show, built once so the
/// desktop card and the web card cannot word a moment differently (the
/// approved mockup, docs/design/mockups/boons-and-bogies-milestones.html).
/// The web gets it as [toJson]; the desktop reads the fields.
class MilestoneView {
  const MilestoneView({
    required this.id,
    required this.kind,
    required this.status,
    required this.seen,
    required this.title,
    required this.pill,
    required this.tierLine,
    required this.text,
    required this.receipt,
    required this.ask,
    required this.ownerName,
    required this.inGroup,
    required this.meter,
  });

  /// Build the view for [moment]. [ring] is the ring it is about (Master,
  /// overcome), [ownerName] the character, [inGroup] whether the card names
  /// them.
  factory MilestoneView.of(
    GrowthMomentData moment, {
    GrowthRingData? ring,
    required String ownerName,
    required bool inGroup,
  }) {
    final kind = MilestoneKind.fromWire(moment.kind);
    final proposal = MilestoneProposal.decode(moment.payload);
    final bogey = switch (kind) {
      MilestoneKind.newBogey ||
      MilestoneKind.masterBogey ||
      MilestoneKind.overcome => true,
      _ => false,
    };
    final name = ownerName.isEmpty ? 'They' : ownerName;
    final text = proposal?.text ?? ring?.content ?? '';
    final receipts =
        proposal?.sourcePositions ??
        (ring == null ? const <int>[] : GrowthStore.receiptsOf(ring));
    return MilestoneView(
      id: moment.id,
      kind: moment.kind,
      status: moment.status,
      seen: moment.seen,
      title: switch (kind) {
        MilestoneKind.newBoon => 'New boon',
        MilestoneKind.newBogey => 'New bogey',
        MilestoneKind.masterBoon => 'Master · boon',
        MilestoneKind.masterBogey => 'Master · bogey',
        MilestoneKind.overcome => 'Bogey overcome',
        null => 'Milestone',
      },
      pill: bogey ? 'BOGEY' : 'BOON',
      tierLine: switch (kind) {
        MilestoneKind.newBoon || MilestoneKind.newBogey => 'Novice · new',
        MilestoneKind.masterBoon =>
          'Skilled → Master · used in ${BoonsBogies.kBoonMasterPasses} scenes',
        MilestoneKind.masterBogey =>
          'Skilled → Master · fired ${BoonsBogies.kBogeyMasterFires} times',
        MilestoneKind.overcome || null =>
          ring == null
              ? ''
              : [
                  _tierWord(BoonsBogies.tierOf(ring)),
                  if (ring.pinned) 'pinned',
                ].join(' · '),
      },
      text: text,
      receipt: receiptLine(receipts, coped: kind == MilestoneKind.overcome),
      ask: switch (kind) {
        MilestoneKind.masterBoon =>
          '$name has mastered this. Keep it for good?',
        MilestoneKind.masterBogey =>
          'This has become part of who $name is. Make it permanent?',
        MilestoneKind.overcome => '$name has overcome this. Let it go?',
        _ => '',
      },
      ownerName: ownerName,
      inGroup: inGroup,
      meter: switch (kind) {
        MilestoneKind.newBoon || MilestoneKind.newBogey => 0.30,
        _ => ring?.strength ?? 0.30,
      },
    );
  }

  final String id;

  /// The wire kind (`new_boon` …) — the celebration it plays.
  final String kind;

  /// pending / accepted / rejected (the wire value; never shown).
  final String status;

  /// What a decided moment's row says: Accepted / Rejected; '' pending.
  String get statusLabel => switch (status) {
    'accepted' => 'Accepted',
    'rejected' => 'Rejected',
    _ => '',
  };
  final bool seen;

  /// "New boon", "Master · bogey", …
  final String title;

  /// BOON or BOGEY.
  final String pill;
  final String tierLine;

  /// The ring sentence (names resolved).
  final String text;

  /// "Seen in #14 and #18" — message numbers as the chat shows them.
  final String receipt;

  /// The question under the ring box; empty for a plain add.
  final String ask;
  final String ownerName;
  final bool inGroup;

  /// 0..1, the ring box's meter.
  final double meter;

  bool get pending => status == 'pending';
  bool get isBogey => pill == 'BOGEY';

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind,
    'status': status,
    'statusLabel': statusLabel,
    'seen': seen,
    'title': title,
    'pill': pill,
    'tierLine': tierLine,
    'text': text,
    'receipt': receipt,
    'ask': ask,
    'ownerName': ownerName,
    'inGroup': inGroup,
    'meter': meter,
  };

  /// Message positions (0-based) as the chat numbers them (#1 first).
  static String receiptLine(List<int> positions, {bool coped = false}) {
    if (positions.isEmpty) return '';
    final nums = [for (final p in positions.take(3)) '#${p + 1}'];
    final list = nums.length == 1
        ? nums.single
        : '${nums.sublist(0, nums.length - 1).join(', ')} and ${nums.last}';
    return '${coped ? 'Coped in' : 'Seen in'} $list';
  }

  static String _tierWord(String tier) => switch (tier) {
    'master' => 'Master',
    'skilled' => 'Skilled',
    _ => 'Novice',
  };
}
