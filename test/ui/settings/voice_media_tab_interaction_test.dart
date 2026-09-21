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

// Voice & Media tab interaction net — required by the god-file campaign's
// provability rule BEFORE voice_media_tab.dart is split. Nothing anywhere
// tapped this tab (settings_persistence_test only opens the Generation tab,
// and TabBarView keeps unvisited tabs unbuilt). Pins a landmark per future
// part file and drives one real control.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:record/record.dart' show InputDevice;

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/settings/tabs/voice_media_tab.dart';

import '../../golden/support/fakes.dart';
import '../../golden/support/fakes_services.dart';
import '../../golden/support/fakes_storage.dart';

/// Voice/media members the shared fake never needed before this net.
class _FakeClassifier extends ChangeNotifier
    implements ExpressionClassifierService {
  @override
  bool get modelReady => false;
  @override
  bool get isModelCached => false;
  @override
  bool get isDownloading => false;
  @override
  OnnxDownloadProgress? get downloadProgress => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SttWithModel extends FakeSttService {
  @override
  bool get isSelectedModelDownloaded => true;
  @override
  get inputDevices => const [];
  @override
  bool get isDownloading => false;
  @override
  Future<List<InputDevice>> refreshInputDevices() async => const [];
}

class _ModelsManager extends FakeModelManager {
  @override
  get models => const [];
}

class _VoiceStorage extends FakeStorageService {
  _VoiceStorage() {
    expressionSettings.setExpressionFallback('none');
    expressionSettings.setExpressionEnabled(true);
    sttSettings.setWhisperModel('base.en');
    sttSettings.setCallBufferSentences(2);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('every section of the Voice & Media tab renders and takes taps', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final storage = _VoiceStorage();
    final tts = FakeTtsService();
    final stt = _SttWithModel();
    final vm = FakeVoiceManager();
    final mm = _ModelsManager();
    final llm = FakeLLMProvider();
    final classifier = _FakeClassifier();
    addTearDown(() {
      storage.dispose();
      tts.dispose();
      stt.dispose();
      vm.dispose();
      mm.dispose();
      llm.dispose();
      classifier.dispose();
    });

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<StorageService>.value(value: storage),
          ChangeNotifierProvider<TtsService>.value(value: tts),
          ChangeNotifierProvider<SttService>.value(value: stt),
          ChangeNotifierProvider<VoiceManager>.value(value: vm),
          ChangeNotifierProvider<ModelManager>.value(value: mm),
          ChangeNotifierProvider<LLMProvider>.value(value: llm),
          ChangeNotifierProvider<ExpressionClassifierService>.value(
            value: classifier,
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: VoiceMediaTab(
              onDragCallBufferChanged: (_) {},
              availableModels: const [],
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    // Landmarks for the always-visible future parts.
    for (final landmark in [
      'Enable Voice Input', // stt part
      'Expression Images', // expressions part
    ]) {
      expect(
        find.textContaining(landmark),
        findsWidgets,
        reason:
            '"$landmark" landmark missing — its future part would be '
            'detached',
      );
    }
    // The call section (voice_call part) is gated behind voice input.
    expect(
      find.textContaining('Call System Prompt'),
      findsNothing,
      reason: 'call settings must stay hidden while voice input is off',
    );

    // Drive the REAL gate end-to-end: enable voice input via its actual
    // switch and the call section (the future voice_call part) must appear.
    final sttSwitch = find.byType(Switch).first;
    await tester.scrollUntilVisible(
      sttSwitch,
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(sttSwitch, warnIfMissed: true);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    final callLandmark = find.textContaining('Call System Prompt');
    await tester.scrollUntilVisible(
      callLandmark,
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      callLandmark,
      findsWidgets,
      reason:
          'enabling voice input must reveal the call section — its '
          'future part would otherwise be detached',
    );
  });
}
