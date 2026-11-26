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

import 'package:flutter/foundation.dart' show debugPrint;

/// A proposed add, as `growth_moments.payload` stores it: the ring text
/// (names resolved), its category and the messages that showed it — and,
/// for a new bogey the Growth pass linked (phase 7), the boon ring id that
/// pushes against it. Exported by `growth_milestones.dart`.
class MilestoneProposal {
  const MilestoneProposal({
    required this.text,
    required this.category,
    this.sourcePositions = const [],
    this.linkedBoon,
  });

  final String text;
  final String category;
  final List<int> sourcePositions;

  /// The linked boon's ring id for a new bogey; null for none. An older
  /// payload without the key reads as unlinked.
  final String? linkedBoon;

  String encode() => jsonEncode({
    'text': text,
    'category': category,
    'src': sourcePositions,
    'linkedBoon': ?linkedBoon,
  });

  static MilestoneProposal? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      final link = m['linkedBoon'];
      return MilestoneProposal(
        text: '${m['text'] ?? ''}',
        category: '${m['category'] ?? ''}',
        sourcePositions: [
          for (final p in (m['src'] as List? ?? const []))
            if (p is int) p,
        ],
        linkedBoon: link is String && link.isNotEmpty ? link : null,
      );
    } catch (e) {
      debugPrint('[Milestones] unreadable payload: $e');
      return null;
    }
  }
}
