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

// Image Studio's Recent shelf sorts pictures by where they came from. The
// generator only knows that from the asking screen's withImageSource, so
// every screen outside the Studio must wrap its call; an unwrapped one would
// land on the shelf as a Studio picture.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/services/image/image_source.dart';

/// The Studio itself, whose pictures are Studio pictures untagged, and the
/// generator's own insides.
const _untagged = [
  'lib/ui/image_studio/',
  'lib/services/web/facade/image_facade.dart',
  'lib/services/image_gen_service.dart',
  'lib/services/image_gen/',
];

void main() {
  test('every screen outside the Studio tags the pictures it asks for', () {
    final calls = RegExp(r'\.generateImage\(');
    final missing = <String>[];
    final tagged = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final path = p.posix.joinAll(p.split(f.path));
      if (_untagged.any(path.startsWith)) continue;
      final code = f.readAsStringSync();
      if (!calls.hasMatch(code)) continue;
      (code.contains('withImageSource(') ? tagged : missing).add(path);
    }
    expect(missing, isEmpty, reason: 'wrap these in withImageSource');
    // The character creator (desktop and phone), chat, guests and Story
    // Studio (desktop and phone).
    expect(tagged, hasLength(greaterThanOrEqualTo(6)));
  });

  test('the source reaches code running under it, and only there', () async {
    ImageSource? seen;
    await withImageSource(
      const ImageSource(ImageSourceKind.chat, 'Rowan'),
      () async {
        await Future<void>.delayed(Duration.zero);
        seen = currentImageSource;
      },
    );
    expect(seen?.line, 'Chat with Rowan');
    expect(currentImageSource, isNull);
  });

  test('every source has words a person reads', () {
    expect(
      [for (final k in ImageSourceKind.values) ImageSource(k).line],
      [
        'Image Studio · Create',
        'Image Studio · Edit',
        'Character creator',
        'Chat',
        'Guest portrait',
        'Story Studio',
      ],
    );
    expect(ImageSourceKind.fromKey('nope'), isNull);
  });
}
