// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// One rule for who sets the context (maintainer ruling O, 2026-10-05): the
// chosen preset does, while KoboldCpp is the backend and a preset is chosen.
// Every desktop place that sets the context follows it, says why in the same
// words, on the page (not only in a tooltip): Settings → Advanced, Settings →
// Generation, the Model Settings dialog, the character creator's setup step
// and a chat's own settings. The Generation tab and the creator used to let a
// preset user type a context the running preset ignored; Advanced and a
// chat's settings used to lock it on a remote backend too, where a preset
// left chosen is not read and the context is the user's.
//
// The real screens, over the Settings page harness (settings_page_harness).

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/character_creator/creator_state.dart';
import 'package:front_porch_ai/ui/character_creator/steps/setup_step.dart';
import 'package:front_porch_ai/ui/dialogs/chat_settings_generation_section.dart';
import 'package:front_porch_ai/ui/settings/widgets/widgets.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

import '../../golden/support/fakes.dart';
import '../../helpers/model_settings_dialog_harness.dart';
import '../../helpers/settings_page_harness.dart';

/// Chooses a preset that sets a 32k context, on [backend].
Future<void> Function(SettingsPageRig rig) _withPreset(String backend) =>
    (rig) async {
      final preset = File(p.join(rig.store.binDir.path, 'Long chats.kcpps'))
        ..writeAsStringSync(jsonEncode({'contextsize': 32768}));
      await rig.store.backendSettings.setActiveKcppsPath(preset.path);
      await rig.store.backendSettings.setBackendType(backend);
    };

/// Whether taps are kept from [control].
bool _closed(WidgetTester tester, Finder control) => tester
    .widgetList<IgnorePointer>(
      find.ancestor(of: control, matching: find.byType(IgnorePointer)),
    )
    .any((w) => w.ignoring);

final Finder _words = find.text(kPresetOwnsContext);

void main() {
  group('Settings → Generation', () {
    Finder slider() => find.widgetWithText(SliderSetting, 'Context Size');

    testWidgets('KoboldCpp with a preset: locked, and says why', (
      tester,
    ) async {
      await mountSettings(
        tester,
        lastUsedIsB: false,
        before: _withPreset('kobold'),
      );
      await openTab(tester, 'Generation');

      expect(_words, findsOneWidget);
      expect(_closed(tester, slider()), isTrue);
    });

    testWidgets('a preset left chosen on a remote backend: the context is '
        'the user\'s', (tester) async {
      await mountSettings(
        tester,
        lastUsedIsB: false,
        before: _withPreset('openRouter'),
      );
      await openTab(tester, 'Generation');

      expect(_words, findsNothing);
      expect(_closed(tester, slider()), isFalse);
    });
  });

  group('Settings → Advanced', () {
    Finder card() => find.text('Context Window');

    testWidgets('KoboldCpp with a preset: locked, and says why', (
      tester,
    ) async {
      await mountSettings(
        tester,
        lastUsedIsB: false,
        before: _withPreset('kobold'),
      );
      await openTab(tester, 'Advanced');

      expect(_words, findsOneWidget);
      expect(_closed(tester, card()), isTrue);
    });

    testWidgets('a preset left chosen on a remote backend: the context is '
        'the user\'s', (tester) async {
      await mountSettings(
        tester,
        lastUsedIsB: false,
        before: _withPreset('openRouter'),
      );
      await openTab(tester, 'Advanced');

      expect(_words, findsNothing);
      expect(_closed(tester, card()), isFalse);
    });
  });

  testWidgets('the Model Settings dialog: KoboldCpp with a preset locks the '
      'context box and says why on the page', (tester) async {
    await openModelSettings(
      tester,
      lastUsedIsB: false,
      before: _withPreset('kobold'),
    );

    expect(_words, findsOneWidget);
    expect(
      _closed(tester, find.widgetWithText(TextField, 'Context Size')),
      isTrue,
    );
  });

  testWidgets('the creator\'s setup step: KoboldCpp with a preset locks the '
      'context box and says why', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 2600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final rig = await buildRig(
      tester,
      lastUsedIsB: false,
      before: _withPreset('kobold'),
    );
    final creator = CreatorState()..extraSettingsExpanded = true;
    addTearDown(creator.dispose);
    await tester.pumpWidget(
      withRigProviders(
        rig,
        child: MaterialApp(
          home: Scaffold(body: SetupStep(state: creator)),
        ),
      ),
    );
    await settle(tester);

    expect(_words, findsOneWidget);
    expect(
      _closed(tester, find.widgetWithText(TextField, 'Context Size')),
      isTrue,
    );
  });

  group('a chat\'s own settings', () {
    Future<void> show(WidgetTester tester, String backend) async {
      final rig = await buildRig(
        tester,
        lastUsedIsB: false,
        before: _withPreset(backend),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ChatSettingsGenerationSection(
                gen: ChatGenerationSettings(),
                storage: rig.store,
                llmProvider: FakeLLMProvider(),
                isRemote: backend != 'kobold',
                onChanged: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    Finder slider() => find.widgetWithText(SliderWithInput, 'Context Size');

    testWidgets('KoboldCpp with a preset: locked, and says why on the page', (
      tester,
    ) async {
      await show(tester, 'kobold');

      expect(_words, findsOneWidget);
      expect(_closed(tester, slider()), isTrue);
    });

    testWidgets('a preset left chosen on a remote backend: the context is '
        'the chat\'s own', (tester) async {
      await show(tester, 'openRouter');

      expect(_words, findsNothing);
      expect(_closed(tester, slider()), isFalse);
    });
  });
}
