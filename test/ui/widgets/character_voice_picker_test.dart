// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// The per-character voice picker (2026-08-14) — the control that made an
// invisible, unclearable override visible and clearable. What it must do:
//  - name the GLOBAL voice on the "use the global voice" option, so the user
//    can see what they'd fall back to;
//  - keep an assigned voice VISIBLE even when the active engine doesn't
//    offer it (a card imported with a Piper voice while Kokoro is selected),
//    because a voice you can't see is a voice you can't clear;
//  - emit '' — never null — when the global option is chosen, since '' is
//    what the save path maps to "follow the global".
//
// Red-proven: dropping the not-available-here DropdownMenuItem makes
// 'an assigned voice from another engine is still shown' fail (Dropdown
// asserts on a value with no matching item).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

import '../../golden/support/fakes_services.dart';
import '../../golden/support/fakes_storage.dart';

class _VoiceStorage extends FakeStorageService {
  _VoiceStorage(this._voice) {
    ttsSettings.setTtsVoiceModel(_voice);
    ttsSettings.setTtsEngine('kokoro');
  }
  final String _voice;
}

void main() {
  Future<void> pump(
    WidgetTester tester, {
    required String globalVoice,
    required String? value,
    required ValueChanged<String> onChanged,
  }) async {
    final storage = _VoiceStorage(globalVoice);
    final tts = TtsService(storage, FakeVoiceManager());
    addTearDown(tts.dispose);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<StorageService>.value(value: storage),
          ChangeNotifierProvider<TtsService>.value(value: tts),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: CharacterVoicePicker(value: value, onChanged: onChanged),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('with no assigned voice, the global option names the global '
      'voice', (tester) async {
    await pump(tester, globalVoice: 'am_adam', value: '', onChanged: (_) {});
    expect(find.textContaining('Use the global voice'), findsOneWidget);
    expect(find.textContaining('Adam'), findsOneWidget);
  });

  testWidgets('with no global voice picked, the option says so instead of '
      'showing an empty paren', (tester) async {
    await pump(tester, globalVoice: '', value: '', onChanged: (_) {});
    expect(find.textContaining('none picked yet'), findsOneWidget);
  });

  testWidgets('an assigned voice from another engine is still shown, '
      'labelled', (tester) async {
    await pump(
      tester,
      globalVoice: 'af_heart',
      // A Piper-style id: not in the Kokoro catalog the active engine offers.
      value: 'en_US-lessac-medium',
      onChanged: (_) {},
    );
    expect(
      find.textContaining('not available on this engine'),
      findsOneWidget,
      reason: 'an override you cannot see is an override you cannot clear',
    );
  });

  testWidgets('the global option carries the EMPTY value the save path '
      'maps to "follow the global voice"', (tester) async {
    // The dropdown emits its selected item's value verbatim, so pinning the
    // option's value pins what onChanged delivers. (Driving the overlay
    // itself is not viable here — the menu route needs a real surface.)
    await pump(
      tester,
      globalVoice: 'af_heart',
      value: 'am_adam',
      onChanged: (_) {},
    );
    final button = tester.widget<DropdownButton<String>>(
      find.byType(DropdownButton<String>),
    );
    expect(button.value, 'am_adam', reason: 'shows the assigned voice');
    final globalItem = button.items!.first;
    expect(
      globalItem.value,
      '',
      reason: "'' is what the save path maps to null = follow the global",
    );
    expect(
      button.items!.map((i) => i.value),
      contains('am_adam'),
      reason: 'the assigned voice must have an item, or Dropdown asserts',
    );
  });

  test('labelFor falls back to a readable form for an unknown id', () {
    expect(
      CharacterVoicePicker.labelFor('am_adam', const []),
      'Adam (am_adam)',
    );
    expect(CharacterVoicePicker.labelFor('plainid', const []), 'plainid');
  });
}
