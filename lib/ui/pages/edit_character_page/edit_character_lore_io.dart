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
import 'dart:typed_data';

import 'package:front_porch_ai/models/models.dart';

/// Parses a lorebook import file (SillyTavern, Chub.ai or Front Porch JSON).
/// Throws [FormatException] with a user-facing message for a wrong shape.
Lorebook parseLorebookImport(List<int> bytes) {
  final content = utf8.decode(bytes);
  final dynamic jsonData = jsonDecode(content);

  if (jsonData is! Map<String, dynamic>) {
    throw FormatException('Invalid JSON format: expected a JSON object');
  }

  final Map<String, dynamic> json = jsonData;

  if (json['entries'] == null && json['lorebook'] == null) {
    throw FormatException(
      'Invalid lorebook file: missing "entries" or "lorebook" field. '
      'Supported formats: SillyTavern, Chub.ai, Front Porch.',
    );
  }

  return Lorebook.fromJson(json);
}

/// World-info JSON bytes, the same shape the importer already accepts.
Uint8List encodeLorebookExport(List<LorebookEntry> selected, String name) {
  final payload = encodeStWorldInfo(
    Lorebook(entries: List<LorebookEntry>.from(selected)),
    name: name,
  );
  return utf8.encode(const JsonEncoder.withIndent('  ').convert(payload));
}

String lorebookExportFileName(String characterName) {
  final safe = characterName
      .trim()
      .replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');
  final stem = safe.isEmpty ? 'lorebook' : safe;
  return '${stem}_lorebook.json';
}
