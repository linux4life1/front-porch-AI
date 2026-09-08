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

/// One run of honesty / markdown-lite text. [bold] is a closed `**…**` span.
class WaifuEmphasisSpan {
  const WaifuEmphasisSpan(this.text, {this.bold = false});

  final String text;
  final bool bold;
}

/// Split `**bold**` markers into runs. Unclosed `**` stays visible sludge.
List<WaifuEmphasisSpan> waifuEmphasisSpans(String raw) {
  if (raw.isEmpty) return const [];
  final out = <WaifuEmphasisSpan>[];
  var i = 0;
  var bold = false;
  final buf = StringBuffer();
  void flush() {
    if (buf.isEmpty) return;
    out.add(WaifuEmphasisSpan(buf.toString(), bold: bold));
    buf.clear();
  }

  while (i < raw.length) {
    if (i + 1 < raw.length && raw[i] == '*' && raw[i + 1] == '*') {
      final closer = raw.indexOf('**', i + 2);
      if (!bold && closer < 0) {
        buf.write('**');
        i += 2;
        continue;
      }
      flush();
      bold = !bold;
      i += 2;
      continue;
    }
    buf.write(raw[i]);
    i++;
  }
  if (bold && buf.isNotEmpty) {
    // Unclosed closer: put the leftover `**` back so we do not invent bold.
    final leftover = buf.toString();
    buf
      ..clear()
      ..write('**')
      ..write(leftover);
    bold = false;
  }
  flush();
  return out;
}

/// Visible text with `**` markers stripped from closed pairs only.
String waifuEmphasisPlain(String raw) =>
    waifuEmphasisSpans(raw).map((s) => s.text).join();
