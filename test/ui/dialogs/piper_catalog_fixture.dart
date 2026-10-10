// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// A few entries of Piper's real voices.json (rhasspy/piper-voices), in the
// shape VoiceManager caches on disk as `system/piper_voices/catalog.json`.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

Map<String, Object> _voice(
  String key,
  String name,
  String code,
  String languageEnglish,
  String countryEnglish,
  String quality,
) {
  final family = code.split('_').first;
  final dir = '$family/$code/$name/$quality';
  return {
    'key': key,
    'name': name,
    'language': {
      'code': code,
      'family': family,
      'region': code.split('_').last,
      'name_native': languageEnglish,
      'name_english': languageEnglish,
      'country_english': countryEnglish,
    },
    'quality': quality,
    'num_speakers': 1,
    'speaker_id_map': <String, int>{},
    'files': {
      '$dir/$key.onnx': {
        'size_bytes': 63201294,
        'md5_digest': '778d28aeb95fcdf8a882344d9df142fc',
      },
      '$dir/$key.onnx.json': {
        'size_bytes': 4882,
        'md5_digest': '7f37dadb26340c90ceeb1f1a7a3a6c6d',
      },
      '$dir/MODEL_CARD': {
        'size_bytes': 281,
        'md5_digest': 'c3ad7ab08ad11d3e8d5f1d0eb2e2f4a1',
      },
    },
    'aliases': <String>[],
  };
}

final String piperCatalogJson = jsonEncode({
  for (final v in [
    _voice(
      'en_GB-alba-medium',
      'alba',
      'en_GB',
      'English',
      'Great Britain',
      'medium',
    ),
    _voice(
      'en_US-amy-medium',
      'amy',
      'en_US',
      'English',
      'United States',
      'medium',
    ),
    _voice(
      'en_US-ryan-high',
      'ryan',
      'en_US',
      'English',
      'United States',
      'high',
    ),
    _voice(
      'de_DE-thorsten-medium',
      'thorsten',
      'de_DE',
      'German',
      'Germany',
      'medium',
    ),
  ])
    v['key'] as String: v,
});

/// Lay out [root] the way VoiceManager finds it after a past visit to the
/// voice browser: the cached catalog, plus [installed] voices registered by
/// their `.onnx.json` config. The configs are empty JSON on purpose: the
/// installed list is read from their file names only.
Future<void> seedPiperVoices(
  String root, {
  List<String> installed = const [],
}) async {
  final dir = Directory(p.join(root, 'system', 'piper_voices'));
  await dir.create(recursive: true);
  await File(p.join(dir.path, 'catalog.json')).writeAsString(piperCatalogJson);
  for (final key in installed) {
    await File(p.join(dir.path, '$key.onnx.json')).writeAsString('{}');
  }
}
