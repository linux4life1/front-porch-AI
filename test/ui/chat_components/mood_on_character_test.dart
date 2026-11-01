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

// Mood on the character on the desktop: the portrait ring paints only when
// there is something to paint, the needs grid throbs a need in trouble
// (hygiene inverted for a character who enjoys it low) only at a level
// that asks for it, the sidebar frame reads the chat's own Realism state
// and nothing with Realism off, and the latest bubble wears its stamped
// mood at the full level only.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/mood_atmosphere.dart';
import 'package:front_porch_ai/services/chat/mood_physics.dart';
import 'package:front_porch_ai/ui/chat_components/mood/mood_bubble.dart';
import 'package:front_porch_ai/ui/chat_components/mood/mood_look.dart';
import 'package:front_porch_ai/ui/chat_components/mood/mood_portrait_frame.dart';
import 'package:front_porch_ai/ui/chat_components/mood/mood_ring.dart';
import 'package:front_porch_ai/ui/theme/appearance_options.dart';
import 'package:front_porch_ai/ui/widgets/needs_bar.dart';
import '../../golden/support/fakes.dart';

const _portrait = MoodLook(MoodOnCharacter.portrait, 1.0);
const _all = MoodLook(MoodOnCharacter.all, 1.0);

MoodAtmosphere _mood(String label, String intensity) =>
    MoodAtmosphere.of(MoodState(label: label, intensity: intensity), drama: 1);

Future<void> _pump(WidgetTester tester, Widget child) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: Center(child: SizedBox(width: 300, child: child)),
    ),
  ),
);

FakeChatService _chat({
  bool realism = true,
  String emotion = 'joy',
  String intensity = 'strong',
  Map<String, int> needs = const {'energy': 80, 'hygiene': 80},
  bool enjoysLowHygiene = false,
}) {
  final chat = FakeChatService(
    realismEnabled: realism,
    needsSimEnabled: true,
    characterEmotion: emotion,
    emotionIntensity: intensity,
    activeCharacter: CharacterCard(
      name: 'Carmen',
      frontPorchExtensions: FrontPorchExtensions(
        needsSimEnabled: true,
        enjoysLowHygiene: enjoysLowHygiene,
      ),
    ),
  );
  chat.needsSimulation.restoreFromSnapshot({'vector': needs});
  return chat;
}

void main() {
  group('MoodRing', () {
    testWidgets('a quiet spec is the bare child; a mood paints a ring', (
      tester,
    ) async {
      const child = SizedBox(key: ValueKey('face'), width: 64, height: 64);
      await _pump(
        tester,
        MoodRing(
          spec: MoodRingSpec(mood: MoodAtmosphere.none, bond: 0, trust: 0),
          child: child,
        ),
      );
      expect(find.byKey(const ValueKey('face')), findsOneWidget);
      expect(find.byKey(const ValueKey('mood-ring')), findsNothing);

      await _pump(
        tester,
        MoodRing(
          spec: MoodRingSpec(mood: _mood('joy', 'strong'), bond: 40, trust: 55),
          animate: false,
          child: child,
        ),
      );
      expect(find.byKey(const ValueKey('mood-ring')), findsOneWidget);
      // A bond alone, or a need alone, paints too.
      await _pump(
        tester,
        MoodRing(
          spec: const MoodRingSpec(
            mood: MoodAtmosphere.none,
            bond: -30,
            trust: 0,
          ),
          animate: false,
          child: child,
        ),
      );
      expect(find.byKey(const ValueKey('mood-ring')), findsOneWidget);
    });
  });

  group('NeedsGrid', () {
    const needs = {'energy': 12, 'hygiene': 92, 'hunger': 70};

    testWidgets(
      'throbs a low need and hammers a critical one only when asked',
      (tester) async {
        await _pump(tester, const NeedsGrid(needs: needs));
        expect(find.byKey(const ValueKey('need-low')), findsNothing);
        expect(find.byKey(const ValueKey('need-critical')), findsNothing);

        await _pump(
          tester,
          const NeedsGrid(needs: needs, pulseInTrouble: true),
        );
        expect(find.byKey(const ValueKey('need-low')), findsOneWidget);
        expect(find.byKey(const ValueKey('need-critical')), findsNothing);
        expect(find.text('!'), findsOneWidget);
      },
    );

    testWidgets('hygiene inverts for a character who enjoys it low', (
      tester,
    ) async {
      await _pump(
        tester,
        const NeedsGrid(
          needs: needs,
          pulseInTrouble: true,
          enjoysLowHygiene: true,
        ),
      );
      // Energy at 12 throbs; hygiene at 92 hammers, marked as inverted.
      expect(find.byKey(const ValueKey('need-low')), findsOneWidget);
      expect(find.byKey(const ValueKey('need-critical')), findsOneWidget);
      expect(find.text('↕'), findsOneWidget);
      expect(find.text('!'), findsOneWidget);
    });
  });

  group('MoodPortraitFrame.specFor', () {
    testWidgets('reads the chat\'s own mood, bond, trust and needs', (
      tester,
    ) async {
      late BuildContext ctx;
      await _pump(
        tester,
        Builder(
          builder: (c) {
            ctx = c;
            return const SizedBox();
          },
        ),
      );
      final chat = _chat(needs: const {'energy': 12, 'hygiene': 80});
      addTearDown(chat.dispose);
      final spec = MoodPortraitFrame.specFor(
        ctx,
        chat,
        chat.activeCharacter!,
        isGroup: false,
        look: _portrait,
      )!;
      expect(spec.mood.tone, MoodTone.lifted);
      expect(spec.mood.strength, closeTo(0.85, 1e-9));
      expect(spec.needHue, isNotNull);

      // Nothing with the level off, or with Realism off for the chat.
      expect(
        MoodPortraitFrame.specFor(
          ctx,
          chat,
          chat.activeCharacter!,
          isGroup: false,
          look: MoodLook.off,
        ),
        isNull,
      );
      final off = _chat(realism: false);
      addTearDown(off.dispose);
      expect(
        MoodPortraitFrame.specFor(
          ctx,
          off,
          off.activeCharacter!,
          isGroup: false,
          look: _portrait,
        ),
        isNull,
      );

      // A quiet mood with needs fine: the spec is there and quiet.
      final calm = _chat(emotion: 'neutral');
      addTearDown(calm.dispose);
      final quiet = MoodPortraitFrame.specFor(
        ctx,
        calm,
        calm.activeCharacter!,
        isGroup: false,
        look: _portrait,
      )!;
      expect(quiet.mood.isOn, isFalse);
      expect(quiet.needHue, isNull);
    });
  });

  group('moodBubbleFrame', () {
    ChatMessage reply(String label) => ChatMessage(
      text: 'She smiles.',
      sender: 'Carmen',
      isUser: false,
      metadata: {'emotion_label': label},
    );

    test(
      'the latest reply wears its stamp at the live loudness, stale stamps mild',
      () {
        final chat = _chat();
        addTearDown(chat.dispose);
        final live = moodBubbleFrame(
          message: reply('joy'),
          character: chat.activeCharacter,
          chat: chat,
          look: _all,
        )!;
        final stale = moodBubbleFrame(
          message: reply('sadness'),
          character: chat.activeCharacter,
          chat: chat,
          look: _all,
        )!;
        expect(live.border.top.width, greaterThan(stale.border.top.width));
        expect(
          live.shadow.single.blurRadius,
          greaterThan(stale.shadow.single.blurRadius),
        );
      },
    );

    test('nothing at the portrait level, for the user, or without a stamp', () {
      final chat = _chat();
      addTearDown(chat.dispose);
      expect(
        moodBubbleFrame(
          message: reply('joy'),
          character: chat.activeCharacter,
          chat: chat,
          look: _portrait,
        ),
        isNull,
      );
      expect(
        moodBubbleFrame(
          message: ChatMessage(
            text: 'Hi',
            sender: 'You',
            isUser: true,
            metadata: {'emotion_label': 'joy'},
          ),
          character: chat.activeCharacter,
          chat: chat,
          look: _all,
        ),
        isNull,
      );
      expect(
        moodBubbleFrame(
          message: ChatMessage(text: 'Hi', sender: 'Carmen', isUser: false),
          character: chat.activeCharacter,
          chat: chat,
          look: _all,
        ),
        isNull,
      );
    });
  });
}
