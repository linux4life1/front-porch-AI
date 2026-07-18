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

import 'package:front_porch_ai/models/lorebook_codec.dart';
import 'package:front_porch_ai/models/lorebook_entry.dart';

export 'package:front_porch_ai/models/lorebook_entry.dart';

/// A collection of lorebook entries plus the V2 character_book book-level
/// settings (stored for round-trip; the scan engine adopts them in the
/// engine-parity phase).
class Lorebook {
  List<LorebookEntry> entries;
  int? scanDepth;
  int? tokenBudget;
  bool? recursiveScanning;

  /// Unknown book-level fields preserved for lossless round-trip.
  Map<String, dynamic> extensions;

  Lorebook({
    required this.entries,
    this.scanDepth,
    this.tokenBudget,
    this.recursiveScanning,
    Map<String, dynamic>? extensions,
  }) : extensions = extensions ?? <String, dynamic>{};

  /// Internal FPAI blob shape (what the DB columns store).
  Map<String, dynamic> toJson() {
    return {
      'entries': entries.map((e) => e.toJson()).toList(),
      if (scanDepth != null) 'scan_depth': scanDepth,
      if (tokenBudget != null) 'token_budget': tokenBudget,
      if (recursiveScanning != null) 'recursive_scanning': recursiveScanning,
      if (extensions.isNotEmpty) 'extensions': extensions,
    };
  }

  /// Tolerant decode of any supported shape: FPAI blob, ST world info,
  /// V2/V3 character_book, NovelAI, AgnAI, or RisuAI (see lorebook_codec).
  factory Lorebook.fromJson(Map<String, dynamic> json) => decodeLorebook(json);

  /// Parse a raw JSON object that may be in SillyTavern, Chub.ai, or Front
  /// Porch format. Returns a Map with 'name', 'description', and 'lorebook'
  /// keys suitable for World creation.
  static Map<String, dynamic> parseRawLorebookJson(Map<String, dynamic> json) {
    final String name = json['name']?.toString() ?? 'Imported Lorebook';
    final String description = json['description']?.toString() ?? '';

    return {
      'name': name,
      'description': description,
      'lorebook': Lorebook.fromJson(json).toJson(),
    };
  }
}
