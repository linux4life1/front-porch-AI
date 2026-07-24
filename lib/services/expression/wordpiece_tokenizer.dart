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

import 'package:unorm_dart/unorm_dart.dart' as unorm;

/// Pure-Dart BERT WordPiece tokenizer matching HuggingFace's uncased
/// `BertTokenizer` pipeline: lowercasing, NFD accent stripping, punctuation
/// splitting, CJK isolation, then greedy longest-match WordPiece. Shared by
/// the expression classifier and the RAG embedding engine (phase 5) — the
/// embedding goldens pin it to fastembed's tokenizers-crate output, so
/// changes here must keep BOTH golden suites green
/// (test/services/expression/wordpiece_tokenizer_test.dart and
/// test/services/embedding/nomic_embedding_test.dart).
class WordPieceTokenizer {
  final Map<String, int> _vocab;
  final int clsId;
  final int sepId;
  final int unkId;
  static const int _maxWordChars = 100;

  WordPieceTokenizer(this._vocab)
    : clsId = _vocab['[CLS]'] ?? 101,
      sepId = _vocab['[SEP]'] ?? 102,
      unkId = _vocab['[UNK]'] ?? 100;

  /// Encodes [text] as `[CLS] ...pieces... [SEP]`, truncated so the total
  /// length is at most [maxLength] (matching HF truncation=True semantics).
  List<int> encode(String text, {int maxLength = 512}) {
    final pieces = <int>[];
    for (final word in _basicTokenize(text)) {
      _wordPiece(word, pieces);
      if (pieces.length > maxLength) break; // no point tokenizing further
    }
    final kept = pieces.length > maxLength - 2
        ? pieces.sublist(0, maxLength - 2)
        : pieces;
    return [clsId, ...kept, sepId];
  }

  /// BasicTokenizer: clean → CJK spacing → whitespace split → per-token
  /// lowercase + accent strip + punctuation split.
  List<String> _basicTokenize(String text) {
    final cleaned = StringBuffer();
    for (final cp in text.runes) {
      if (cp == 0 || cp == 0xFFFD || _isControl(cp)) continue;
      if (_isWhitespace(cp)) {
        cleaned.writeCharCode(0x20);
      } else if (_isCjk(cp)) {
        cleaned
          ..writeCharCode(0x20)
          ..writeCharCode(cp)
          ..writeCharCode(0x20);
      } else {
        cleaned.writeCharCode(cp);
      }
    }
    final out = <String>[];
    for (final raw in cleaned.toString().split(' ')) {
      if (raw.isEmpty) continue;
      final word = _stripAccents(raw.toLowerCase());
      // Split punctuation into standalone tokens.
      final buf = StringBuffer();
      for (final cp in word.runes) {
        if (_isPunctuation(cp)) {
          if (buf.isNotEmpty) {
            out.add(buf.toString());
            buf.clear();
          }
          out.add(String.fromCharCode(cp));
        } else {
          buf.writeCharCode(cp);
        }
      }
      if (buf.isNotEmpty) out.add(buf.toString());
    }
    return out;
  }

  /// Greedy longest-match WordPiece; a word with any unmatchable remainder
  /// becomes a single [UNK] (HF behavior).
  void _wordPiece(String word, List<int> out) {
    final chars = word.runes.toList();
    if (chars.length > _maxWordChars) {
      out.add(unkId);
      return;
    }
    final ids = <int>[];
    var start = 0;
    while (start < chars.length) {
      var end = chars.length;
      int? found;
      while (start < end) {
        var sub = String.fromCharCodes(chars.sublist(start, end));
        if (start > 0) sub = '##$sub';
        final id = _vocab[sub];
        if (id != null) {
          found = id;
          break;
        }
        end--;
      }
      if (found == null) {
        out.add(unkId);
        return;
      }
      ids.add(found);
      start = end;
    }
    out.addAll(ids);
  }

  static bool _isWhitespace(int cp) =>
      cp == 0x20 ||
      cp == 0x09 ||
      cp == 0x0A ||
      cp == 0x0D ||
      cp == 0xA0 ||
      (cp >= 0x2000 && cp <= 0x200A) ||
      cp == 0x2028 ||
      cp == 0x2029 ||
      cp == 0x202F ||
      cp == 0x205F ||
      cp == 0x3000;

  static bool _isControl(int cp) =>
      (cp < 0x20 && cp != 0x09 && cp != 0x0A && cp != 0x0D) ||
      cp == 0x7F ||
      (cp >= 0x80 && cp <= 0x9F) ||
      (cp >= 0x200B && cp <= 0x200F) || // zero-width + directional marks (Cf)
      (cp >= 0x202A && cp <= 0x202E) ||
      cp == 0xFEFF;

  /// Unicode category P approximation: full ASCII punctuation plus the
  /// blocks that show up in chat text (general punctuation, CJK punctuation,
  /// fullwidth forms, inverted marks).
  static bool _isPunctuation(int cp) =>
      (cp >= 0x21 && cp <= 0x2F) ||
      (cp >= 0x3A && cp <= 0x40) ||
      (cp >= 0x5B && cp <= 0x60) ||
      (cp >= 0x7B && cp <= 0x7E) ||
      cp == 0xA1 ||
      cp == 0xBF ||
      cp == 0xAB ||
      cp == 0xBB ||
      cp == 0xB7 ||
      (cp >= 0x2010 && cp <= 0x2027) ||
      (cp >= 0x2030 && cp <= 0x205E) ||
      (cp >= 0x3001 && cp <= 0x3011) ||
      (cp >= 0xFF01 && cp <= 0xFF0F) ||
      (cp >= 0xFF1A && cp <= 0xFF20) ||
      (cp >= 0xFF3B && cp <= 0xFF40) ||
      (cp >= 0xFF5B && cp <= 0xFF65);

  static bool _isCjk(int cp) =>
      (cp >= 0x4E00 && cp <= 0x9FFF) ||
      (cp >= 0x3400 && cp <= 0x4DBF) ||
      (cp >= 0xF900 && cp <= 0xFAFF) ||
      (cp >= 0x20000 && cp <= 0x2A6DF) ||
      (cp >= 0x2A700 && cp <= 0x2CEAF) ||
      (cp >= 0x2F800 && cp <= 0x2FA1F);

  /// True NFD accent strip, matching HF's BertNormalizer exactly: decompose
  /// (unorm NFD), then drop combining marks. Applied after lowercasing,
  /// mirroring HF's lower() → NFD-strip order.
  ///
  /// This replaced a Latin-only precomposed→base lookup table after the
  /// phase-5 embedding goldens caught the difference: NFD-stripping applies
  /// to EVERY script — Japanese voiced kana (が → か + U+3099, mark
  /// dropped), Greek/Cyrillic/Vietnamese diacritics — and the table's
  /// Latin-only view made those tokenize as [UNK] where the reference
  /// stacks produced real tokens.
  static String _stripAccents(String s) {
    final buf = StringBuffer();
    for (final cp in unorm.nfd(s).runes) {
      if (_isCombiningMark(cp)) continue;
      buf.writeCharCode(cp);
    }
    return buf.toString();
  }

  /// Combining marks (Unicode category Mn) that NFD decomposition can emit,
  /// plus the standalone combining blocks — the set HF's strip_accents
  /// removes for real-world text.
  static bool _isCombiningMark(int cp) =>
      (cp >= 0x0300 && cp <= 0x036F) || // Combining Diacritical Marks
      (cp >= 0x0483 && cp <= 0x0489) || // Cyrillic combining
      (cp >= 0x0591 && cp <= 0x05C7) || // Hebrew points
      (cp >= 0x0610 && cp <= 0x061A) || // Arabic marks
      (cp >= 0x064B && cp <= 0x065F) ||
      cp == 0x0670 ||
      (cp >= 0x06D6 && cp <= 0x06DC) ||
      (cp >= 0x06DF && cp <= 0x06E4) ||
      (cp >= 0x06E7 && cp <= 0x06E8) ||
      (cp >= 0x06EA && cp <= 0x06ED) ||
      cp == 0x093C || cp == 0x09BC || cp == 0x0A3C || // Indic nukta
      cp == 0x0ABC || cp == 0x0B3C || cp == 0x0CBC ||
      (cp >= 0x1AB0 && cp <= 0x1AFF) || // Combining Extended
      (cp >= 0x1DC0 && cp <= 0x1DFF) || // Combining Supplement
      (cp >= 0x20D0 && cp <= 0x20FF) || // Marks for Symbols
      (cp >= 0x3099 && cp <= 0x309A) || // Kana voicing marks
      (cp >= 0xFE20 && cp <= 0xFE2F); // Combining Half Marks
}
