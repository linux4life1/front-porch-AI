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

// The TTS settings dialog's interaction net — required by the god-file
// campaign's provability rule BEFORE tts_settings_dialog.dart is split. Its
// only prior coverage was a golden pumping engine='disabled', in which state
// ~925 of the file's 1,474 lines (all four engine sections) never render at
// all. This net drives the REAL segmented engine selector through all four
// engines and pins a landmark inside each section — the exact code the split
// moves into per-engine part files.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/dialogs/tts_settings_dialog.dart';

import '../../golden/support/fakes.dart';
import '../../golden/support/fakes_services.dart';
import '../../golden/support/fakes_storage.dart';

/// The shared fake pins ttsEngine to 'disabled'; the net needs the selector
/// to actually switch sections, so make it mutable + notify like the real
/// StorageService would.
/// The shared fake throws on unknown members; the Kokoro section genuinely
/// asks whether the model is on disk — answer "no" so its Download card
/// renders (the deepest branch the golden never reached).
class _TtsWithModelProbe extends FakeTtsService {
  @override
  Future<bool> isModelDownloaded() async => false;
}

class _StorageWithEngine extends FakeStorageService {
  _StorageWithEngine() {
    ttsSettings.setTtsEngine('kokoro');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the engine selector walks all four engine sections', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final storage = _StorageWithEngine();
    final tts = _TtsWithModelProbe();
    final vm = FakeVoiceManager();
    addTearDown(() {
      storage.dispose();
      tts.dispose();
      vm.dispose();
    });

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<StorageService>.value(value: storage),
          ChangeNotifierProvider<TtsService>.value(value: tts),
          ChangeNotifierProvider<VoiceManager>.value(value: vm),
        ],
        child: const MaterialApp(home: Material(child: TtsSettingsDialog())),
      ),
    );
    // Bounded pumps, not settle: async voice loads run in initState.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    Future<void> pick(String tab) async {
      await tester.tap(find.textContaining(tab), warnIfMissed: true);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
    }

    // Kokoro is the starting engine — its section renders voices/model card.
    expect(
      find.textContaining('Kokoro'),
      findsWidgets,
      reason: 'Kokoro tab must exist',
    );

    await pick('OpenAI');
    expect(
      find.text('API Key'),
      findsWidgets,
      reason:
          'OpenAI section (its future part file) did not render after '
          'tapping its REAL engine tab',
    );

    await pick('ElevenLabs');
    expect(
      find.text('API Key'),
      findsWidgets,
      reason: 'ElevenLabs section did not render',
    );

    await pick('Piper');
    expect(
      find.text('Browse'),
      findsWidgets,
      reason: 'Piper section (Browse voices button) did not render',
    );

    await pick('Kokoro');
    expect(
      find.text('Browse'),
      findsNothing,
      reason: 'switching back must swap the section out again',
    );
  });
}
