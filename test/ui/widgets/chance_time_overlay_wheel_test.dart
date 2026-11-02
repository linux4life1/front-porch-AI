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

// The desktop Chance Time overlay on its Flame wheel: SPIN picks the slot
// before the wheel moves and the wheel lands on that slot (outcome first),
// the card waits for the landing and the settle, the shown event is the
// landed slot's, the wheel takes no focus, and under reduce motion the
// wheel jumps so the card shows at once with nothing in motion.

import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/chat/chaos/chance_spin.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/widgets/chance_time_overlay.dart';
import 'package:front_porch_ai/ui/widgets/chance_time_overlay/chance_time_overlay.dart';
import 'package:provider/provider.dart';

import '../../golden/support/fakes.dart';

const _events = [
  'fortune:{{char}} finds a coin.',
  'misfortune:{{char}} trips.',
  'chaos:{{char}} hears thunder.',
  'wildcard:{{char}} meets a stranger.',
  'fortune:{{char}} gets a letter.',
  'misfortune:{{char}} spills tea.',
  'chaos:{{char}} loses the lights.',
  'wildcard:{{char}} remembers a song.',
];

/// The overlay's host, standing in for the chat's chance door; the golden
/// fake still serves the pressure row.
class _Host implements ChanceTimeHost {
  int triggersConsumed = 0;
  String? applied;

  @override
  void consumeTrigger() => triggersConsumed++;

  @override
  List<String> spinWheelEvents() => _events;

  @override
  String get speakerName => 'Carmen';

  @override
  String resolve(String raw, String charName) =>
      raw.replaceAll('{{char}}', charName);

  @override
  Future<void> apply(String event, String charName) async {
    applied = event;
  }
}

Future<_Host> _pump(WidgetTester tester, {bool reduceMotion = false}) async {
  final host = _Host();
  final chat = FakeChatService();
  addTearDown(chat.dispose);
  await tester.pumpWidget(
    ChangeNotifierProvider<ChatService>.value(
      value: chat,
      child: MediaQuery(
        data: MediaQueryData(
          size: const Size(900, 900),
          disableAnimations: reduceMotion,
        ),
        child: MaterialApp(
          home: Scaffold(body: ChanceTimeOverlay(host: host)),
        ),
      ),
    ),
  );
  // The overlay loads its events on the next frame; the game mounts its
  // wheel over the frames after.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 50));
  return host;
}

ChanceWheelGame _game(WidgetTester tester) => tester
    .widget<GameWidget<ChanceWheelGame>>(
      find.byType(GameWidget<ChanceWheelGame>),
    )
    .game!;

void main() {
  testWidgets('SPIN decides the slot first and the wheel lands on it; the '
      'card waits for the settle and shows that slot\'s event', (tester) async {
    final host = await _pump(tester);
    expect(host.triggersConsumed, 1);
    expect(find.text('SPIN'), findsOneWidget);
    final game = _game(tester);
    expect(game.segments, _events);
    expect(find.byType(ChanceTimeResultCard), findsNothing);

    await tester.tap(find.text('SPIN'));
    await tester.pump();
    final sim = game.sim!;
    final slot = sim.plan.slot;
    expect(sim.started, isTrue);
    expect(find.text('SPIN'), findsNothing);

    // Mid-spin: moving, no card.
    await tester.pump(const Duration(seconds: 2));
    expect(sim.landed, isFalse);
    expect(sim.omega.abs(), greaterThan(0));
    expect(sim.clicks, greaterThan(0));
    expect(find.byType(ChanceTimeResultCard), findsNothing);

    // Landed, settling: still no card.
    await tester.pump(const Duration(milliseconds: 2400));
    expect(sim.landed, isTrue);
    expect(find.byType(ChanceTimeResultCard), findsNothing);

    // Settled: the card, with the landed slot's event, for the speaker.
    await tester.pump(const Duration(milliseconds: 700));
    expect(sim.settled, isTrue);
    expect(chanceSlotUnderPointer(sim.angle), slot);
    expect(find.byType(ChanceTimeResultCard), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(
      find.text(_events[slot].replaceAll('{{char}}', 'Carmen')),
      findsOneWidget,
    );
    expect(find.textContaining('{{char}}'), findsNothing);
    expect(find.text('Accept Your Fate 🎲'), findsOneWidget);
  });

  testWidgets('under reduce motion the wheel jumps to its slot and the card '
      'shows at once with nothing in motion', (tester) async {
    await _pump(tester, reduceMotion: true);
    await tester.tap(find.text('SPIN'));
    await tester.pump();
    final sim = _game(tester).sim!;
    expect(sim.settled, isTrue);
    expect(sim.omega, 0);
    expect(sim.clicks, 0);
    expect(chanceSlotUnderPointer(sim.angle), sim.plan.slot);
    expect(find.byType(ChanceTimeResultCard), findsOneWidget);
    expect(
      find.text(_events[sim.plan.slot].replaceAll('{{char}}', 'Carmen')),
      findsOneWidget,
    );
    // No particles were thrown.
    expect(
      _game(tester).children.whereType<ParticleSystemComponent>(),
      isEmpty,
    );
  });

  testWidgets('the wheel takes no focus and no input', (tester) async {
    await _pump(tester);
    final stage = find.byType(GameWidget<ChanceWheelGame>);
    expect(tester.widget<GameWidget<ChanceWheelGame>>(stage).autofocus, false);
    expect(
      find.ancestor(of: stage, matching: find.byType(IgnorePointer)),
      findsWidgets,
    );
    expect(
      find.ancestor(of: stage, matching: find.byType(ExcludeFocus)),
      findsWidgets,
    );
  });
}
