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

/// SmolVLM-500M-Instruct prompt construction + output decoding for the
/// offline photo captioner (see LocalCaptionService).
///
/// The caption prompt is FIXED, so no BPE *encoder* is needed anywhere:
/// every token id below was dumped from the reference HF processor for the
/// exact template
///   `<|im_start|>User:<image>Describe this image in detail.<end_of_utterance>\nAssistant:`
/// and [buildPromptIds] reassembles the Idefics3 image-placeholder expansion
/// for whatever tile grid the preprocessor produced. Only the *decode*
/// direction (generated ids → text) needs the vocabulary, which
/// [SmolVlmVocabDecoder] reads from the downloaded tokenizer.json.

/// `<|im_start|>` — BOS.
const int kSmolVlmBos = 1;

/// "User:" after BOS.
const List<int> kSmolVlmUserPrefix = [11126, 42];

/// `<fake_token_around_image>`.
const int kSmolVlmFakeImage = 49189;

/// `<image>` — placeholder replaced by vision features (64 per frame).
const int kSmolVlmImageToken = 49190;

/// `<global-img>` — marks the downscaled whole-image frame.
const int kSmolVlmGlobalImg = 49152;

/// "\n" between tile rows, "\n\n" before the global frame block.
const int kSmolVlmNewline = 198;
const int kSmolVlmDoubleNewline = 1116;

/// "Describe this image in detail." (the fixed instruction).
const List<int> kSmolVlmInstruction = [37964, 451, 2443, 281, 2202, 30];

/// `<end_of_utterance>` — also the generation stop token (shares the id with
/// EOS in this tokenizer config).
const int kSmolVlmEndOfUtterance = 49279;

/// "\nAssistant:" — generation prompt.
const List<int> kSmolVlmAssistantSuffix = [198, 9519, 9531, 42];

/// Vision tokens per 512×512 frame (pixel-shuffle output length).
const int kSmolVlmTokensPerFrame = 64;

/// `<row_R_col_C>` ids are laid out arithmetically after `<global-img>`
/// (verified against tokenizer.json: row stride 6, cols 1-6).
int smolVlmRowColToken(int row, int col) => 49152 + (row - 1) * 6 + col;

/// Assemble the full prompt ids for a [rows]×[cols] tile grid (+ the global
/// frame), mirroring the Idefics3 processor expansion byte-for-byte:
/// per row: `<fake><row_R_col_C><image>×64` per tile, then `\n`; after the
/// last row an extra `\n` (making `\n\n` — the single-token form), then
/// `<fake><global-img><image>×64<fake>`, instruction, `<end_of_utterance>`,
/// and `\nAssistant:`.
List<int> buildSmolVlmPromptIds({required int rows, required int cols}) {
  final ids = <int>[kSmolVlmBos, ...kSmolVlmUserPrefix];
  for (var r = 1; r <= rows; r++) {
    for (var c = 1; c <= cols; c++) {
      ids.add(kSmolVlmFakeImage);
      ids.add(smolVlmRowColToken(r, c));
      ids.addAll(List.filled(kSmolVlmTokensPerFrame, kSmolVlmImageToken));
    }
    // Row separator; the final row's "\n" merges with the pre-global "\n"
    // into the single "\n\n" token, exactly as the BPE would produce.
    if (r < rows) ids.add(kSmolVlmNewline);
  }
  ids.add(kSmolVlmDoubleNewline);
  ids.add(kSmolVlmFakeImage);
  ids.add(kSmolVlmGlobalImg);
  ids.addAll(List.filled(kSmolVlmTokensPerFrame, kSmolVlmImageToken));
  ids.add(kSmolVlmFakeImage);
  ids.addAll(kSmolVlmInstruction);
  ids.add(kSmolVlmEndOfUtterance);
  ids.addAll(kSmolVlmAssistantSuffix);
  return ids;
}

/// Decode-only tokenizer over the model's tokenizer.json: id → token string →
/// GPT-2 byte-level reversal → UTF-8. Special/added tokens are skipped, so
/// the decoded caption is clean prose.
class SmolVlmVocabDecoder {
  final Map<int, String> _idToToken;
  final Set<int> _specialIds;
  final Map<int, int> _charToByte;

  SmolVlmVocabDecoder._(this._idToToken, this._specialIds, this._charToByte);

  /// Parse the HF tokenizer.json content (vocab + added_tokens).
  factory SmolVlmVocabDecoder.fromTokenizerJson(String jsonText) {
    final root = jsonDecode(jsonText) as Map<String, dynamic>;
    final vocab =
        ((root['model'] as Map<String, dynamic>)['vocab']
            as Map<String, dynamic>);
    final idToToken = <int, String>{
      for (final e in vocab.entries) e.value as int: e.key,
    };
    final special = <int>{};
    for (final t in (root['added_tokens'] as List<dynamic>? ?? const [])) {
      final m = t as Map<String, dynamic>;
      special.add(m['id'] as int);
      idToToken[m['id'] as int] = m['content'] as String;
    }
    return SmolVlmVocabDecoder._(idToToken, special, _buildCharToByte());
  }

  /// GPT-2 byte-level map inverse: printable ranges keep their code points;
  /// the remaining bytes were remapped to 256+n at training time.
  static Map<int, int> _buildCharToByte() {
    final bs = <int>[
      for (var b = 33; b <= 126; b++) b,
      for (var b = 161; b <= 172; b++) b,
      for (var b = 174; b <= 255; b++) b,
    ];
    final cs = List<int>.from(bs);
    var n = 0;
    for (var b = 0; b < 256; b++) {
      if (!bs.contains(b)) {
        bs.add(b);
        cs.add(256 + n);
        n++;
      }
    }
    return {for (var i = 0; i < bs.length; i++) cs[i]: bs[i]};
  }

  /// Decode generated ids to text, skipping special/added tokens.
  String decode(List<int> ids) {
    final bytes = <int>[];
    for (final id in ids) {
      if (_specialIds.contains(id)) continue;
      final token = _idToToken[id];
      if (token == null) continue;
      for (final rune in token.runes) {
        final b = _charToByte[rune];
        if (b != null) bytes.add(b);
      }
    }
    return utf8.decode(bytes, allowMalformed: true).trim();
  }
}
