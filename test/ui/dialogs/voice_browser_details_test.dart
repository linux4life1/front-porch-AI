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

// The Voice Model Browser's row details. A voice whose gender the app does
// not know used to read "Albanian (Albania) • ⚬ Unknown • medium", which
// looks like two stray bullets in a row; a custom import showed empty
// brackets. Now an unknown gender is simply left out, and so are the
// brackets when there is no country. Known genders still show.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/dialogs/voice_browser_dialog.dart';

/// Holds a catalog the way the real manager does after a fetch; no network.
class _CatalogVoices extends ChangeNotifier implements VoiceManager {
  _CatalogVoices(this.catalog, this.installed);

  @override
  final List<PiperVoice> catalog;
  final List<String> installed;

  @override
  bool get isLoadingCatalog => false;
  @override
  Future<void> fetchCatalog() async {}
  @override
  Future<List<String>> listInstalledVoices() async => installed;
  @override
  bool isDownloading(String voiceKey) => false;
  @override
  double getDownloadProgress(String voiceKey) => 0;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

PiperVoice _voice(String name, String language, String country) => PiperVoice(
  key: '${language}_$name-medium',
  name: name,
  languageCode: 'xx',
  languageEnglish: language,
  countryEnglish: country,
  quality: 'medium',
  numSpeakers: 1,
  files: {'v.onnx': PiperVoiceFile(sizeBytes: 63569920, md5Digest: '')},
);

void main() {
  testWidgets('a voice with no known gender shows no gender and no stray '
      'bullets; a known gender still shows', (tester) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    // The 120 px Quality box overflows in the test font, as the dialog's
    // golden already allows for; the rows are what this test reads.
    final previousOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.exceptionAsString().contains('overflowed')) return;
      previousOnError?.call(details);
    };
    addTearDown(() => FlutterError.onError = previousOnError);
    final voices = _CatalogVoices(
      [
        _voice('edon', 'Albanian', 'Albania'),
        _voice('kareem', 'Arabic', 'Jordan'),
      ],
      ['my_custom_voice'],
    );
    addTearDown(voices.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChangeNotifierProvider<VoiceManager>.value(
            value: voices,
            child: const VoiceBrowserDialog(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Albanian (Albania) • medium • 60.6 MB'), findsOneWidget);
    expect(
      find.text('Arabic (Jordan) • ♂ Male • medium • 60.6 MB'),
      findsOneWidget,
    );
    // An imported voice has no catalog entry: no country, no gender.
    expect(find.text('Custom import • custom • 0.0 MB'), findsOneWidget);
    expect(find.textContaining('Unknown'), findsNothing);
    expect(find.textContaining('⚬'), findsNothing);
    expect(find.textContaining('()'), findsNothing);
  });
}
