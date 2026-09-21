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

/// Cleaning narrative text before it becomes image-prompt source material.
///
/// This is deliberately NOT `utils/think_tags.dart`'s `stripThinkTags`. The
/// visual path cuts from the LAST `<think>` rather than the first and removes
/// stray tags of any shape, because what it is protecting against is a
/// half-generated bubble whose thought fragments would otherwise be distilled
/// into a picture. Three places needed that exact behaviour — the prompt
/// builder, the chat scene dialogs, and the Image Studio source pills — and all
/// three used to carry their own copy of it.
library;

/// The think steps, without the whitespace collapse, so callers that insert
/// their own removals can do so before the text is squeezed onto one line.
String _stripThinkParts(String text) {
  var out = text.replaceAll(
    RegExp(r'<\/?think>.*?<\/think>', dotAll: true, caseSensitive: false),
    '',
  );
  final lastOpen = out.toLowerCase().lastIndexOf('<think>');
  if (lastOpen != -1) out = out.substring(0, lastOpen);
  return out.replaceAll(RegExp(r'<\/?think[^>]*>', caseSensitive: false), '');
}

String _squeeze(String text) => text.replaceAll(RegExp(r'\s{2,}'), ' ').trim();

/// Drop the line a card import leaves behind. It names a character and reads
/// like prose, so a distiller will happily draw it.
String _dropCardImportLine(String text) => text.replaceAll(
  RegExp(
    r'Auto-imported from character card:.*?(?:\n|$)',
    caseSensitive: false,
  ),
  '',
);

/// Reasoning out, one line in. For callers that do their own extra removals
/// afterwards (the prompt builder strips interrupted-eval notices too).
String stripThinkForVisual(String text) {
  if (text.isEmpty) return text;
  return _squeeze(_stripThinkParts(text));
}

/// Reasoning and card-import meta out: what a source pill or a scene snapshot
/// shows the user and hands to the distiller.
String cleanVisualSourceText(String text) {
  if (text.isEmpty) return text;
  return _squeeze(_dropCardImportLine(_stripThinkParts(text)));
}
