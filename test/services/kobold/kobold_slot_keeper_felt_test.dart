// What keeping a chat costs is only the wait the user feels (maintainer
// ruling, 2026-10-05): a save runs right after the reply appears, while the
// user reads and types, so it costs nothing when it is done before the next
// message, and what is left of it when the next turn starts otherwise. The
// load before a reply always counts. The previous turn's passes that wait
// behind the save are not the user's wait. Through the real service on the
// engine stand-in, which holds each save as a slow copy would.

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/services.dart';

import '../../helpers/kobold_engine_harness.dart';

/// About 300 tokens of chat: read again in 0.3 s at 1,000 tokens a second.
final String _chat = [for (var i = 0; i < 300; i++) 'w$i'].join(' ');

GenerationParams _reply(int turn) => GenerationParams(
  prompt: '$_chat turn $turn',
  systemPrompt: 'RULES',
  maxLength: 16,
  kvChat: 'A',
);

/// A check of the turn, or a pass of the turn before: any other prompt.
GenerationParams _helper(String what) =>
    GenerationParams(prompt: 'a $what', maxLength: 8);

void main() {
  late KoboldEngineHarness h;
  late Duration saveTakes;

  setUp(() async {
    h = await KoboldEngineHarness.start();
    addTearDown(h.dispose);
    h.kobold.debugKeeperPlan = () async => const KoboldKeeperPlan.keep(3);
    // What KoboldCpp prints after a request: 1,000 tokens read a second.
    h.kobold.debugEngineSaid(
      'Processed:2000 in 2.00s (1000.00T/s), '
      'Generated:16/16 in 0.50s (32.00T/s)\n',
    );
    saveTakes = Duration.zero;
    h.engine.beforeAdmin = (r) => r.kind == 'save'
        ? Future<void>.delayed(saveTakes)
        : Future<void>.value();
  });

  /// Streams [params] to its end; a reply's save then starts.
  Future<void> ask(GenerationParams params) =>
      h.kobold.generateStream(params).toList();

  List<String> letGo() => [
    for (final l in h.kobold.logs)
      if (l.contains('to read it again')) l,
  ];

  /// The first two turns: the first save only makes the slot; the second
  /// turn's reply ends with its save running.
  Future<void> twoTurns() async {
    await ask(_reply(1));
    await h.kobold.waitForIdle();
    h.kobold.noteTurnStart();
    await ask(_helper('check of turn 2'));
    await ask(_reply(2));
  }

  /// The third turn's check and reply, then the save after it.
  Future<void> thirdTurn() async {
    await ask(_helper('check of turn 3'));
    h.engine.forgetLog();
    await ask(_reply(3));
    await h.kobold.waitForIdle();
  }

  test('a slow save that is done before the next message costs nothing: '
      'the chat is kept', () async {
    saveTakes = const Duration(milliseconds: 600);
    await twoTurns();
    await h.kobold.waitForIdle(); // the user reads and types meanwhile

    h.kobold.noteTurnStart();
    await thirdTurn();

    expect(letGo(), isEmpty);
    expect(h.engine.kinds, ['load', 'chat', 'save'], reason: 'not kept');
  });

  test('a save still running when the next message comes: what is left of '
      'it counts, and only that', () async {
    saveTakes = const Duration(milliseconds: 1000);
    await twoTurns();
    // The next message 850 ms into a 1 s save: 0.15 s left to wait, less
    // than the 0.3 s reading the chat again would take.
    await Future<void>.delayed(const Duration(milliseconds: 850));
    h.kobold.noteTurnStart();
    await ask(_helper('check of turn 3')); // it waited; the save was weighed
    expect(letGo(), isEmpty, reason: 'the whole save was counted');

    await ask(_reply(3));
    // The next message at once: all of the 1 s save after reply 3 is left,
    // more than a reading.
    h.kobold.noteTurnStart();
    await ask(_helper('check of turn 4'));
    expect(letGo(), hasLength(1), reason: 'the wait left was not counted');
  });

  test('the turn before\'s passes that wait behind the save are not the '
      'user\'s wait', () async {
    saveTakes = const Duration(milliseconds: 600);
    await twoTurns();
    // Asked right after the reply, as the journal and growth passes are:
    // they wait for the save, and the user is still reading.
    await ask(_helper('journal pass of turn 2'));
    await ask(_helper('growth pass of turn 2'));

    h.kobold.noteTurnStart();
    await thirdTurn();

    expect(letGo(), isEmpty);
    expect(h.engine.kinds, ['load', 'chat', 'save'], reason: 'not kept');
  });
}
