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

/// The steps a lorebook import takes after the file is decoded, shared by the
/// desktop Import Lorebook wizard and the web relay.
///
/// Decoding was always shared (`Lorebook.fromJson`, `detectLorebookFormat`,
/// `LorebookImportSummary`). What the two surfaces each wrote for themselves
/// was everything after it: cloning the book so the import cannot alias the
/// file it came from, picking a free world name, and merging entries into a
/// group's stored JSON. Three chances for one of them to drift.
///
/// How the result is phrased stays with each caller — the wizard writes a
/// sentence for a human, the relay returns JSON for the PWA.
library;

import 'dart:convert';

import 'package:front_porch_ai/models/lorebook.dart';

/// A deep copy of [source]. Imports must never hand out entries that are still
/// shared with the parsed file, or editing the destination edits the source.
Lorebook cloneLorebook(Lorebook source) => Lorebook(
  entries: [for (final e in source.entries) e.clone()],
  scanDepth: source.scanDepth,
  tokenBudget: source.tokenBudget,
  recursiveScanning: source.recursiveScanning,
  extensions: Map<String, dynamic>.from(source.extensions),
);

/// Append [incoming] to a group's stored lorebook JSON and return the new JSON.
/// An empty or unreadable column starts a fresh book rather than throwing —
/// a group whose lore never loaded should still be able to receive an import.
String appendToGroupLorebookJson(
  String existingJson,
  List<LorebookEntry> incoming,
) {
  Lorebook book;
  if (existingJson.isEmpty) {
    book = Lorebook(entries: []);
  } else {
    try {
      book = Lorebook.fromJson(
        jsonDecode(existingJson) as Map<String, dynamic>,
      );
    } catch (_) {
      book = Lorebook(entries: []);
    }
  }
  book.entries.addAll(incoming);
  return jsonEncode(book.toJson());
}
