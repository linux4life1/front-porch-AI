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

@Tags(['golden'])
@TestOn('linux')
library;

// Pixels for the redesigned Settings tabs (PRs 716-719). The structural
// guards — settings_parity_manifest_test, one_ui_parity_test — check which
// controls exist and on which tab; they stayed green over a control whose
// painted element had been hidden by its own CSS. These goldens pin how the
// three redesigned tabs actually render, so the next redesign cannot drift
// silently. Baselines regenerate on the Linux CI image (Update Goldens
// workflow); the phone surface is the same widget at phone width, the One
// UI rule checked in pixels.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/storage/storage.dart';
import 'package:front_porch_ai/ui/settings/tabs/tabs.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';

import '../support/fakes.dart';
import '../support/fakes_storage.dart';
import '../support/golden_app.dart';

const _group = 'settings_tabs';

/// The house helper pumps its own MaterialApp brightness and knows nothing
/// about AppearanceSettings, whose mode defaults to dark. [ThemeCardGrid]
/// faithfully follows the model, so without this the light goldens painted
/// every theme card — including the selected one — in its dark palette:
/// a cream page advertising a dark gallery. The production app can never
/// diverge (its root derives the MaterialApp theme from this same model);
/// the test tree must not fake a state the app cannot hold.
class _SyncBrightnessToModel extends StatefulWidget {
  const _SyncBrightnessToModel({required this.child});

  final Widget child;

  @override
  State<_SyncBrightnessToModel> createState() => _SyncBrightnessToModelState();
}

class _SyncBrightnessToModelState extends State<_SyncBrightnessToModel> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final dark = Theme.of(context).brightness == Brightness.dark;
    final appearance = context.read<StorageService>().appearance;
    final wanted = dark ? AppThemeMode.dark : AppThemeMode.light;
    if (appearance.mode != wanted) {
      appearance.setMode(wanted);
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// The dialog-audited house fake plus the members only the Settings tabs
/// read (the appearance model, the generation-preset store, and the static
/// spell-check language the house fake otherwise routes to noSuchMethod).
class _SettingsStorage extends FakeStorageService {
  _SettingsStorage() {
    appearance.initializeBase(null, notifyListeners);
    genPresets.initializeBase(null, notifyListeners);
  }

  @override
  final AppearanceSettings appearance = AppearanceSettings();
  @override
  final GenPresetSettings genPresets = GenPresetSettings();

  @override
  String get spellCheckLanguage => 'en_US';
}

void main() {
  testWidgets('General, Appearance and Generation render on wide and phone', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final storage = _SettingsStorage();
    addTearDown(storage.dispose);
    final systemPrompt = TextEditingController(
      text: 'You are a helpful assistant.',
    );
    final banned = TextEditingController(text: '');
    addTearDown(systemPrompt.dispose);
    addTearDown(banned.dispose);

    final tabs = <String, Widget Function()>{
      'general': () => GeneralTab(systemPromptController: systemPrompt),
      'appearance': () => const AppearanceTab(),
      'generation': () => GenerationTab(bannedPhrasesController: banned),
    };
    const surfaces = {'wide': Size(1440, 2600), 'phone': Size(400, 3200)};

    for (final tab in tabs.entries) {
      for (final surface in surfaces.entries) {
        await expectThemedGoldens(
          tester,
          childBuilder: () => MultiProvider(
            providers: [
              ChangeNotifierProvider<StorageService>.value(value: storage),
              ChangeNotifierProvider<LLMProvider>(
                create: (_) => FakeLLMProvider(),
              ),
              ChangeNotifierProvider<ChatService>(
                create: (_) => FakeChatService(),
              ),
            ],
            child: _SyncBrightnessToModel(child: tab.value()),
          ),
          group: _group,
          name: '${tab.key}_${surface.key}',
          surface: surface.value,
          settle: false,
        );
      }
    }
  });
}
