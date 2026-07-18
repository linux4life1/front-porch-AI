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

import 'package:front_porch_ai/models/lorebook.dart';

/// Lorebook container formats we can decode. Detection markers mirror
/// SillyTavern's importWorldInfo exactly, so anything ST can read, we can.
enum LorebookFormat {
  /// FPAI internal blob, ST world info, or V2 character_book — all share the
  /// tolerant per-entry decoder, so they need no container-level distinction.
  fpaiOrSt,

  /// V3 standalone `{spec: 'lorebook_v3', data: {…}}` (or a chara_card_v3
  /// wrapper passed whole).
  v3Lorebook,

  /// NovelAI lorebook: `lorebookVersion` present.
  novelAi,

  /// AgnAI memory book: `kind == 'memory'`.
  agnai,

  /// RisuAI lorebook: `type == 'risu'`.
  risu,
}

LorebookFormat detectLorebookFormat(Map<String, dynamic> json) {
  if (json['lorebookVersion'] != null) return LorebookFormat.novelAi;
  if (json['kind'] == 'memory') return LorebookFormat.agnai;
  if (json['type'] == 'risu') return LorebookFormat.risu;
  final spec = json['spec']?.toString() ?? '';
  if (spec == 'lorebook_v3' || spec == 'chara_card_v3') {
    return LorebookFormat.v3Lorebook;
  }
  return LorebookFormat.fpaiOrSt;
}

/// Single tolerant decode entry point (backs `Lorebook.fromJson`).
Lorebook decodeLorebook(Map<String, dynamic> json) {
  switch (detectLorebookFormat(json)) {
    case LorebookFormat.novelAi:
      return _decodeNovelAi(json);
    case LorebookFormat.agnai:
      return _decodeAgnai(json);
    case LorebookFormat.risu:
      return _decodeRisu(json);
    case LorebookFormat.v3Lorebook:
      final data = json['data'] is Map
          ? Map<String, dynamic>.from(json['data'] as Map)
          : json;
      // chara_card_v3 wrapper: the book sits at data.character_book.
      final book = data['character_book'] is Map
          ? Map<String, dynamic>.from(data['character_book'] as Map)
          : data;
      return _decodeNative(book);
    case LorebookFormat.fpaiOrSt:
      return _decodeNative(json);
  }
}

/// FPAI blob / ST world info / V2 character_book. Entries may be a List
/// (FPAI, V2) or a Map keyed by uid string (ST `{"0": {…}}`).
Lorebook _decodeNative(Map<String, dynamic> json) {
  final dynamic entriesData = json['entries'];
  List<Map<String, dynamic>> entriesList = [];

  if (entriesData is List) {
    entriesList = entriesData
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  } else if (entriesData is Map) {
    entriesList = entriesData.values
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  return Lorebook(
    entries: entriesList.map(LorebookEntry.fromJson).toList(),
    scanDepth: _asInt(json['scan_depth']),
    tokenBudget: _asInt(json['token_budget']),
    recursiveScanning:
        json['recursive_scanning'] is bool ? json['recursive_scanning'] as bool : null,
    extensions: json['extensions'] is Map
        ? Map<String, dynamic>.from(json['extensions'] as Map)
        : null,
  );
}

/// NovelAI: entries[].keys / .text / .displayName / .enabled /
/// .contextConfig.budgetPriority → order.
Lorebook _decodeNovelAi(Map<String, dynamic> json) {
  final entries = <LorebookEntry>[];
  final raw = json['entries'];
  if (raw is List) {
    for (final e in raw.whereType<Map>()) {
      final ctx = e['contextConfig'];
      entries.add(LorebookEntry(
        name: e['displayName']?.toString() ?? '',
        keys: _strings(e['keys']),
        content: e['text']?.toString() ?? '',
        enabled: e['enabled'] != false,
        order: _asInt(ctx is Map ? ctx['budgetPriority'] : null) ?? 100,
      ));
    }
  }
  return Lorebook(entries: entries);
}

/// AgnAI memory book: entries[].keywords / .name / .entry / .weight → order.
Lorebook _decodeAgnai(Map<String, dynamic> json) {
  final entries = <LorebookEntry>[];
  final raw = json['entries'];
  if (raw is List) {
    for (final e in raw.whereType<Map>()) {
      entries.add(LorebookEntry(
        name: e['name']?.toString() ?? '',
        keys: _strings(e['keywords']),
        content: e['entry']?.toString() ?? '',
        enabled: e['enabled'] != false,
        order: _asInt(e['weight']) ?? 100,
      ));
    }
  }
  return Lorebook(entries: entries);
}

/// RisuAI: data[].key (comma string) / .secondkey / .comment / .content /
/// .alwaysActive → constant / .insertorder → order /
/// .activationPercent → probability.
Lorebook _decodeRisu(Map<String, dynamic> json) {
  final entries = <LorebookEntry>[];
  final raw = json['data'];
  if (raw is List) {
    for (final e in raw.whereType<Map>()) {
      final selective = e['selective'] == true;
      final probability = _asInt(e['activationPercent']);
      entries.add(LorebookEntry(
        name: e['comment']?.toString() ?? '',
        key: e['key']?.toString() ?? '',
        secondaryKeys: selective
            ? LorebookEntry.parseKeyList(e['secondkey']?.toString() ?? '')
            : null,
        content: e['content']?.toString() ?? '',
        constant: e['alwaysActive'] == true,
        selective: selective,
        order: _asInt(e['insertorder']) ?? 100,
        probability: probability ?? 100,
        useProbability: probability != null,
      ));
    }
  }
  return Lorebook(entries: entries);
}

int? _asInt(dynamic v) => v is int ? v : (v is num ? v.toInt() : null);

List<String> _strings(dynamic v) => v is List
    ? v
        .where((x) => x != null)
        .map((x) => x.toString().trim())
        .where((s) => s.isNotEmpty)
        .toList()
    : <String>[];
