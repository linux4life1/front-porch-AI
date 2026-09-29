// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Talks to the real civitai.com. The version endpoint is public, so no key
// is needed, but the test only runs when CIVITAI_LIVE is set so a CI runner
// without network cannot go red for it. It never downloads a model.
//
//   CIVITAI_LIVE=1 flutter test --tags live test/services/image/civitai_live_test.dart
@Tags(['live'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/image/image.dart';

void main() {
  final live = Platform.environment.containsKey('CIVITAI_LIVE');
  final skip = live ? null : 'set CIVITAI_LIVE=1 to talk to civitai.com';

  setUp(() {
    // flutter_test swaps in an HttpClient that answers 400 to everything.
    final saved = HttpOverrides.current;
    HttpOverrides.global = null;
    addTearDown(() => HttpOverrides.global = saved);
  });

  for (final id in [133005, 128713, 130072, 1957126, 1236037]) {
    test('version $id still reads the way the saved fixture does', () async {
      final lookup = await fetchCivitaiVersion(versionId: id, adult: false);
      expect(lookup.kind, CivitaiLookupKind.ok);
      final now = lookup.version!;
      final saved = parseCivitaiVersion(
        File('test/fixtures/civitai/version_$id.json').readAsStringSync(),
      )!;
      expect(now.id, saved.id);
      expect(now.modelType, saved.modelType);
      expect(now.files.map((f) => f.name), saved.files.map((f) => f.name));
      for (var i = 0; i < saved.files.length; i++) {
        expect(now.files[i].sizeBytes, saved.files[i].sizeBytes);
        expect(now.files[i].sha256, saved.files[i].sha256);
        expect(now.files[i].format, saved.files[i].format);
        expect(now.files[i].downloadUri, saved.files[i].downloadUri);
      }
    }, skip: skip);
  }

  test('a version that does not exist is "not found", not a crash', () async {
    final lookup = await fetchCivitaiVersion(
      versionId: 999999999,
      adult: false,
    );
    expect(lookup.kind, CivitaiLookupKind.notFound);
    expect(lookup.version, isNull);
  }, skip: skip);

  test('the saved fixtures are valid JSON', () {
    for (final id in [133005, 128713, 130072, 1957126, 1236037]) {
      final body = File(
        'test/fixtures/civitai/version_$id.json',
      ).readAsStringSync();
      expect(jsonDecode(body), isA<Map>());
    }
  });
}
