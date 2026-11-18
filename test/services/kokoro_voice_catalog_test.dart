// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Regression tests for the Kokoro voice catalog and speaker-id resolution.
//
// Reported on Discord (2026-07-31): "Kokoro seems to fall back to a default
// voice and does not use the voice i selected. I tried the adam voice but the
// tts falls back to a female voice." Two independent causes:
//
//   1. The hand-written voice catalog had drifted from the shipped model. It
//      offered jm_beta / em_santa / zm_yibo (all labelled Male), which the
//      kokoro-multi-lang-v1_0 bundle does not contain.
//   2. An unresolvable voice fell straight through to af_heart — a FEMALE
//      voice — silently, so any stale or retired male voice became a woman
//      with nothing logged.
//
// The catalog is now derived from the model's own speaker table, so (1) cannot
// recur by construction; these tests pin that, plus the gender-preserving
// fallback that fixes (2).

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/kokoro_engine.dart';
import 'package:front_porch_ai/services/tts/sherpa_kokoro_engine.dart';

void main() {
  group('Kokoro voice catalog', () {
    test('offers exactly the voices the shipped model contains', () {
      final catalogIds = KokoroEngine.catalog.map((v) => v.id).toSet();
      expect(catalogIds, equals(SherpaKokoroEngine.speakerIds.keys.toSet()));
    });

    test('every offered voice resolves to its own speaker id, never a fallback',
        () {
      for (final voice in KokoroEngine.catalog) {
        expect(
          SherpaKokoroEngine.resolveSpeakerId(voice.id),
          equals(SherpaKokoroEngine.speakerIds[voice.id]),
          reason: '${voice.id} ("${voice.name}") must not hit the fallback',
        );
      }
    });

    test('does offer the three voices the old catalog hid', () {
      final ids = KokoroEngine.catalog.map((v) => v.id);
      expect(ids, contains('jf_nezumi'));
      expect(ids, contains('jf_tebukuro'));
      expect(ids, contains('zm_yunjian'));
    });

    test('derives name, gender and language from the voice id', () {
      final adam = KokoroEngine.catalog.firstWhere((v) => v.id == 'am_adam');
      expect(adam.name, 'Adam');
      expect(adam.gender, 'Male');
      expect(adam.language, 'American English');

      final xiaobei =
          KokoroEngine.catalog.firstWhere((v) => v.id == 'zf_xiaobei');
      expect(xiaobei.name, 'Xiaobei');
      expect(xiaobei.gender, 'Female');
      expect(xiaobei.language, 'Mandarin Chinese');
    });

    test('keeps the default voice first so the picker opens where it used to',
        () {
      expect(KokoroEngine.catalog.first.id, SherpaKokoroEngine.defaultVoice);
    });
  });

  group('speaker-id resolution', () {
    test('Adam resolves to the male speaker the model metadata declares', () {
      // model.onnx embeds the literal table "af_alloy->0,…,am_adam->11,…".
      expect(SherpaKokoroEngine.resolveSpeakerId('am_adam'), 11);
    });

    test('a retired male voice falls back to a male voice, not af_heart', () {
      for (final stale in ['jm_beta', 'em_santa', 'zm_yibo']) {
        final sid = SherpaKokoroEngine.resolveSpeakerId(stale);
        final resolved = SherpaKokoroEngine.speakerIds.entries
            .firstWhere((e) => e.value == sid)
            .key;
        expect(
          resolved[1],
          'm',
          reason: '$stale must not become the female default ($resolved)',
        );
        expect(
          resolved[0],
          stale[0],
          reason: '$stale should stay in its own language ($resolved)',
        );
      }
    });

    test('an unresolvable voice falls back to the documented default', () {
      expect(
        SherpaKokoroEngine.resolveSpeakerId('totally_unknown'),
        SherpaKokoroEngine.speakerIds[SherpaKokoroEngine.defaultVoice],
      );
    });
  });
}
