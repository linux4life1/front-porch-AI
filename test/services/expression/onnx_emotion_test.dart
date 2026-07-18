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

// Cross-language goldens for the in-process emotion classifier (phase 2 of
// docs/design/sidecar-retirement.md). Every expected value below was
// generated from the EXACT Python stack the sentiment sidecar used:
// transformers AutoTokenizer on the model's own vocab/tokenizer files for
// token ids, and onnxruntime + numpy float64 softmax on the real
// Cohee/distilbert-base-uncased-go-emotions-onnx model for logits/scores
// (generated 2026-07-16; see the phase-2 record in the design doc).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/expression/onnx_emotion_engine.dart';
import 'package:front_porch_ai/services/expression/wordpiece_tokenizer.dart';

void main() {
  final vocabFile = File('test/fixtures/emotion_classifier/vocab.txt');
  late WordPieceTokenizer tok;

  setUpAll(() {
    tok = WordPieceTokenizer(OnnxEmotionEngine.loadVocab(vocabFile));
  });

  group('WordPiece tokenizer matches the Python reference tokenizer', () {
    const cases = <String, List<int>>{
      "I'm so happy right now!": [
        101, 1045, 1005, 1049, 2061, 3407, 2157, 2085, 999, 102, //
      ],
      'This is absolutely disgusting and I hate it.': [
        101, 2023, 2003, 7078, 19424, 1998, 1045, 5223, 2009, 1012, 102, //
      ],
      'Thank you so much, that means the world to me.': [
        101, 4067, 2017, 2061, 2172, 1010, 2008, 2965, 1996, 2088, 2000,
        2033, 1012, 102, //
      ],
      'wait... what just happened?': [
        101, 3524, 1012, 1012, 1012, 2054, 2074, 3047, 1029, 102, //
      ],
      // Accent stripping (é è û é ï ç ñ) + em-dash punctuation split.
      'She glanced at the café menu — crème brûlée, naïve façade, El Niño.': [
        101, 2016, 3887, 2012, 1996, 7668, 12183, 1517, 13675, 21382, 7987,
        9307, 2063, 1010, 15743, 8508, 1010, 3449, 20801, 1012, 102, //
      ],
      "NO!!! Don't touch that!!": [
        101, 2053, 999, 999, 999, 2123, 1005, 1056, 3543, 2008, 999, 999,
        102, //
      ],
      // Curly quotes (Pi/Pf) + horizontal ellipsis (Po).
      "he said “it's fine” but it wasn't fine…": [
        101, 2002, 2056, 1523, 2009, 1005, 1055, 2986, 1524, 2021, 2009,
        2347, 1005, 1056, 2986, 1529, 102, //
      ],
      "I guess that's an OK plan, whatever works for everyone else I suppose.":
          [
            101, 1045, 3984, 2008, 1005, 1055, 2019, 7929, 2933, 1010, 3649,
            2573, 2005, 3071, 2842, 1045, 6814, 1012, 102, //
          ],
      // Deep greedy subword splitting of unknown long words.
      'supercalifragilisticexpialidocious floccinaucinihilipilification': [
        101, 3565, 9289, 10128, 29181, 24411, 4588, 10288, 19312, 21273,
        10085, 6313, 13109, 10085, 28748, 14194, 5498, 19466, 11514, 18622,
        10803, 102, //
      ],
      // Emoji word → single [UNK]; CJK chars isolated (some in vocab, some
      // [UNK]).
      '\u{1F60A}\u{1F62D} emojis and 中文字符 mixed with english text': [
        101, 100, 7861, 29147, 2483, 1998, 1746, 1861, 100, 100, 3816,
        2007, 2394, 3793, 102, //
      ],
      "You did WHAT?! I can't believe you would betray me like that after everything we've been through together.":
          [
            101, 2017, 2106, 2054, 1029, 999, 1045, 2064, 1005, 1056, 2903,
            2017, 2052, 20895, 2033, 2066, 2008, 2044, 2673, 2057, 1005, 2310,
            2042, 2083, 2362, 1012, 102, //
          ],
      "*sighs softly* It's been a long day on the porch, hasn't it?": [
        101, 1008, 19906, 5238, 1008, 2009, 1005, 1055, 2042, 1037, 2146,
        2154, 2006, 1996, 7424, 1010, 8440, 1005, 1056, 2009, 1029, 102, //
      ],
    };

    cases.forEach((text, expected) {
      test(text.length > 40 ? '${text.substring(0, 40)}…' : text, () {
        expect(tok.encode(text), expected);
      });
    });

    test('truncates to 512 total tokens keeping [CLS]/[SEP]', () {
      final ids = tok.encode(
        'the porch light flickers every single evening ' * 70,
      );
      expect(ids.length, 512);
      expect(ids.sublist(0, 10), [
        101, 1996, 7424, 2422, 17909, 2015, 2296, 2309, 3944, 1996, //
      ]);
      expect(ids.sublist(502), [
        2296, 2309, 3944, 1996, 7424, 2422, 17909, 2015, 2296, 102, //
      ]);
    });
  });

  group('softmax + 28-label mapping matches the Python model output', () {
    // Raw logits captured from the real ONNX model in Python; expected
    // top-3 from numpy float64 softmax. These also pin the label ORDER —
    // e.g. index 11 must be 'disgust' (the sidecar's 26-entry list shifted
    // it to index 10 and would have called it 'disapproval').
    const happyLogits = [
      0.840766, 0.346659, -2.509898, -2.371778, 1.460946, 1.146209,
      -1.802147, -0.498464, 0.205169, -3.008710, -2.437463, -2.813764,
      -2.483338, 2.727851, -2.521105, 1.619885, -2.493362, 2.610678,
      0.431681, -1.824898, 2.400946, 1.268351, 0.703221, 1.102289,
      -2.060937, -3.206969, 0.347193, -0.970122, //
    ];
    const disgustLogits = [
      -1.989334, -2.178409, 0.141547, -0.433524, -1.059508, -0.827853,
      -0.373242, -0.903566, -0.416047, 0.837223, 2.424422, 3.573331,
      1.634381, -1.460644, -0.145945, -2.277808, 0.251748, -2.383079,
      -2.406399, -1.008078, -2.113457, -1.676100, 0.566826, -2.014298,
      0.504068, 0.303871, -0.625257, -1.709782, //
    ];
    const gratitudeLogits = [
      0.979973, -1.173400, -2.086450, -2.088234, 0.749551, 1.414729,
      -0.758624, -0.134182, -0.469029, -2.860816, -2.105785, -2.198657,
      -1.829098, 0.386881, -1.986109, 2.794379, -1.521101, 0.368463,
      0.156554, -1.111844, 0.266978, 0.573774, 1.971430, 0.849821,
      -1.005048, -1.870358, 0.035784, -0.763578, //
    ];

    void check(List<double> logits, List<(String, double)> expected) {
      final scored = OnnxEmotionEngine.topScores(logits);
      for (var i = 0; i < expected.length; i++) {
        expect(scored[i].$1, expected[i].$1);
        expect(scored[i].$2, closeTo(expected[i].$2, 0.0001));
      }
    }

    test("happy text → excitement/joy/optimism", () {
      check(happyLogits, [
        ('excitement', 0.2153),
        ('joy', 0.1915),
        ('optimism', 0.1553),
      ]);
    });

    test('disgust text → disgust/disapproval/embarrassment', () {
      check(disgustLogits, [
        ('disgust', 0.5247),
        ('disapproval', 0.1663),
        ('embarrassment', 0.0755),
      ]);
    });

    test('gratitude text → gratitude/realization/caring', () {
      check(gratitudeLogits, [
        ('gratitude', 0.3434),
        ('realization', 0.1508),
        ('caring', 0.0864),
      ]);
    });

    test('label list has exactly 28 entries in model order', () {
      expect(OnnxEmotionEngine.labels.length, 28);
      expect(OnnxEmotionEngine.labels[10], 'disapproval');
      expect(OnnxEmotionEngine.labels[23], 'relief');
      expect(OnnxEmotionEngine.labels.last, 'neutral');
    });
  });

  test('loadVocab reads both vocab.txt and tokenizer.json shapes', () async {
    final txtVocab = OnnxEmotionEngine.loadVocab(vocabFile);
    expect(txtVocab['[CLS]'], 101);
    expect(txtVocab['[SEP]'], 102);
    expect(txtVocab['[UNK]'], 100);
    expect(txtVocab.length, 30522);

    final dir = await Directory.systemTemp.createTemp('emo_vocab');
    try {
      final json = File('${dir.path}/tokenizer.json');
      json.writeAsStringSync(
        '{"model":{"vocab":{"[UNK]":100,"[CLS]":101,"hello":7592}}}',
      );
      final jsonVocab = OnnxEmotionEngine.loadVocab(json);
      expect(jsonVocab['hello'], 7592);
      expect(jsonVocab['[CLS]'], 101);
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
