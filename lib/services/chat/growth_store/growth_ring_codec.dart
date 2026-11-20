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

// Small pure decoders shared by the ring writers. Kept out of the writer
// files so both the ordinary and boon/bogey writers can use them without a
// cycle.

import 'dart:convert';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/utils/utils.dart';

/// Decodes a session's groupEvolved* JSON column into charId → text
/// (empty on null/garbage).
Map<String, String> parseEvolvedJsonMap(String? json) {
  if (json == null || json.isEmpty) return {};
  try {
    return (jsonDecode(json) as Map<String, dynamic>).map(
      (k, v) => MapEntry(k, v?.toString() ?? ''),
    );
  } catch (_) {
    return {};
  }
}

/// Merged, deduplicated receipt positions for a ring + new citations.
List<int> mergedGrowthReceipts(GrowthRingData ring, List<int> extra) {
  final merged = <int>{
    ...decodeReceiptIds(ring.sourceMessageIds),
    ...extra,
  }.toList()..sort();
  return merged;
}
