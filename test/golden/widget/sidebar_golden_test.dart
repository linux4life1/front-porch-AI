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

// Widget pixel goldens for the warm-porch chat sidebar (grouped accordions).
// Frozen in light + dark via the shared timer-free `FakeChatService`. The
// Character State golden is the centerpiece: it pins the unified bond/trust/
// LUST bar treatment (the nsfw_section merge) plus fixation, needs, and the
// shared TimeStrip. (Pixel baselines regenerate on the Linux CI runner.)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/models/lorebook.dart';
import 'package:front_porch_ai/services/chat_service.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/ui/chat_components/sidebar/character_state/character_state_group.dart';
import 'package:front_porch_ai/ui/chat_components/sidebar/character_state/character_state_settings.dart';
import 'package:front_porch_ai/ui/chat_components/sidebar/character_state/time_strip.dart';
import 'package:front_porch_ai/ui/chat_components/sidebar/journal_memory/summary_section.dart';
import 'package:front_porch_ai/ui/chat_components/sidebar/porch_accordion.dart';
import 'package:front_porch_ai/ui/chat_components/sidebar/story_tools/author_note_section.dart';
import 'package:front_porch_ai/ui/chat_components/sidebar/story_tools/chaos_panel.dart';
import 'package:front_porch_ai/ui/chat_components/sidebar/story_tools/lorebook_panel.dart';
import 'package:front_porch_ai/ui/chat_components/sidebar/story_tools/objective_panel.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

import '../support/creator_test_support.dart';
import '../support/fakes.dart';
import '../support/golden_app.dart';

/// A sync StorageService (defaults only) for panels that read a setting at
/// build. Its async init is irrelevant to a static golden.
StorageService _storage() {
  SharedPreferences.setMockInitialValues({});
  return StorageService();
}

void main() {
  setupPathProviderMock();

  testWidgets('TimeStrip — evening, day 3', (tester) async {
    final chat = FakeChatService(timeOfDay: 'evening', dayCount: 3);
    addTearDown(chat.dispose);
    await expectThemedGoldens(
      tester,
      child: SizedBox(width: 300, child: TimeStrip(chat: chat)),
      group: 'sidebar',
      name: 'time_strip_evening',
      surface: const Size(340, 120),
    );
  });

  testWidgets('TimeStrip — dawn, day 1', (tester) async {
    final chat = FakeChatService(timeOfDay: 'dawn', dayCount: 1);
    addTearDown(chat.dispose);
    await expectThemedGoldens(
      tester,
      child: SizedBox(width: 300, child: TimeStrip(chat: chat)),
      group: 'sidebar',
      name: 'time_strip_dawn',
      surface: const Size(340, 120),
    );
  });

  testWidgets('PorchAccordion — collapsed and expanded', (tester) async {
    await expectThemedGoldens(
      tester,
      child: Builder(
        builder: (context) => SizedBox(
          width: 320,
          child: Column(
            children: [
              PorchAccordion(
                id: 'demo_collapsed',
                emoji: '🎭',
                title: 'Character State',
                subtitle: 'Fond · Trusting · Evening',
                accent: AppColors.porchTerracottaOf(context),
                child: const Text('body'),
              ),
              PorchAccordion(
                id: 'demo_expanded',
                emoji: '🎲',
                title: 'Story Tools',
                accent: AppColors.porchHoneyOf(context),
                initiallyExpanded: true,
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Text('Expanded body content'),
                ),
              ),
            ],
          ),
        ),
      ),
      group: 'sidebar',
      name: 'porch_accordion',
      surface: const Size(360, 260),
    );
  });

  testWidgets('CharacterStateGroup — 1:1 with Lust bar and fixation',
      (tester) async {
    final chat = FakeChatService(
      activeCharacter: CharacterCard(name: 'Aria Vale'),
      characterEmotion: 'affection',
      emotionIntensity: 'strong',
    );
    addTearDown(chat.dispose);
    // Seed the merged Lust bar (cooldown on, warm arousal, ticking
    // refractory) and an active fixation — the exact surfaces the old
    // separate NSFW box owned.
    chat.nsfwService.loadNsfwScalars(
      nsfwCooldownEnabled: true,
      arousalLevel: 62,
      cooldownTurnsRemaining: 2,
      cooldownTurnsTotal: 4,
    );
    chat.relationshipService.loadScalars(
      affectionScore: 120,
      longTermScore: 60,
      trustLevel: 40,
      activeFixation: 'the lighthouse logs',
      fixationLifespan: 3,
    );
    final storage = _storage();
    addTearDown(storage.dispose);
    await expectThemedGoldens(
      tester,
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider<StorageService>.value(value: storage),
          ChangeNotifierProvider<ChatService>.value(value: chat),
        ],
        child: SizedBox(
          width: 340,
          child: CharacterStateGroup(
            chat: chat,
            isGroup: false,
            initiallyExpanded: true,
          ),
        ),
      ),
      group: 'sidebar',
      name: 'character_state',
      surface: const Size(380, 900),
      settle: false,
    );
  });

  testWidgets('CharacterStateSettings — flyout open', (tester) async {
    final chat = FakeChatService();
    addTearDown(chat.dispose);
    final storage = _storage();
    addTearDown(storage.dispose);
    await expectThemedGoldens(
      tester,
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider<StorageService>.value(value: storage),
          ChangeNotifierProvider<ChatService>.value(value: chat),
        ],
        child: SizedBox(
          width: 320,
          child: CharacterStateSettings(chat: chat, isGroup: false),
        ),
      ),
      group: 'sidebar',
      name: 'character_state_settings',
      surface: const Size(360, 520),
    );
  });

  testWidgets('AuthorNoteSection — populated note', (tester) async {
    final chat = FakeChatService(
      authorNote: '[Keep the tone wry. {{char}} avoids direct answers.]',
      authorNoteStrength: 4,
    );
    addTearDown(chat.dispose);
    await expectThemedGoldens(
      tester,
      child: SizedBox(width: 320, child: AuthorNoteSection(chatService: chat)),
      group: 'sidebar',
      name: 'author_note',
      surface: const Size(360, 360),
      // Owns a text field (blinking-cursor ticker).
      settle: false,
    );
  });

  testWidgets('SummarySection — populated recap', (tester) async {
    final chat = FakeChatService(
      summary: '{{user}} and {{char}} agreed to meet at the harbor at dawn '
          'after {{char}} admitted the lighthouse logs were forged.',
      summaryLastIndex: 12,
    );
    addTearDown(chat.dispose);
    final storage = _storage();
    addTearDown(storage.dispose);
    await expectThemedGoldens(
      tester,
      child: ChangeNotifierProvider<StorageService>.value(
        value: storage,
        child: SizedBox(width: 320, child: SummarySection(chatService: chat)),
      ),
      group: 'sidebar',
      name: 'summary',
      surface: const Size(360, 420),
      settle: false,
      // The Journal is on by default and the body renders inside the
      // accordion now — no expansion tap needed.
    );
  });

  testWidgets('ChaosPanel — enabled with pressure', (tester) async {
    final chat = FakeChatService();
    addTearDown(chat.dispose);
    // Stateless panel — seed the service before rendering to show the
    // enabled state (pressure gauge + spin control).
    chat.chaosModeService.loadScalars(modeEnabled: true, pressure: 60);
    await expectThemedGoldens(
      tester,
      child: SizedBox(
        width: 320,
        child: ChaosPanel(chat: chat, onSpinRequested: () {}),
      ),
      group: 'sidebar',
      name: 'chaos',
      surface: const Size(360, 360),
    );
  });

  testWidgets('LorebookSection — character with entries', (tester) async {
    final character = CharacterCard(
      name: 'Aria Vale',
      lorebook: Lorebook(entries: [
        LorebookEntry(
            key: 'lighthouse', content: 'The lamp at the cape never goes dark.'),
        LorebookEntry(
            key: 'storm', content: 'A wreck washed in last winter; salvage debts linger.'),
      ]),
    );
    await expectThemedGoldens(
      tester,
      child: SizedBox(
        width: 340,
        child: LorebookSection(character: character, activeLore: const {}),
      ),
      group: 'sidebar',
      name: 'lorebook',
      surface: const Size(380, 420),
      settle: false,
    );
  });

  testWidgets('ObjectivePanel — no active objective', (tester) async {
    final chat = FakeChatService();
    addTearDown(chat.dispose);
    await expectThemedGoldens(
      tester,
      // The panel nests a Consumer<ChatService>, so provide it in the tree.
      child: ChangeNotifierProvider<ChatService>.value(
        value: chat,
        child: SizedBox(width: 320, child: ObjectivePanel(chatService: chat)),
      ),
      group: 'sidebar',
      name: 'objective_empty',
      surface: const Size(360, 360),
      settle: false,
    );
  });
}
