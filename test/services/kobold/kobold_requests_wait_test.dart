// Every request that can change what KoboldCpp keeps in its cache goes out
// one at a time, in the order it was asked for: chat replies, tool calls,
// helper streams and the system-role check. Together they used to race, so
// nothing could keep a chat's cache safe between one reply and the next.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/services.dart';

import '../../helpers/fake_kobold_engine.dart';
import '../../helpers/kobold_engine_harness.dart';

GenerationParams _ask(String text) =>
    GenerationParams(prompt: text, maxLength: 16);

const _tools = [
  {
    'type': 'function',
    'function': {
      'name': 'note',
      'description': 'Write a note.',
      'parameters': {
        'type': 'object',
        'properties': {
          'text': {'type': 'string'},
        },
      },
    },
  },
];

Future<void> _until(bool Function() done) async {
  final end = DateTime.now().add(const Duration(seconds: 10));
  while (!done()) {
    if (DateTime.now().isAfter(end)) fail('waited 10 s for something');
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

Future<void> _nextTurn() => Future<void>.delayed(Duration.zero);

/// Long enough for a request sent too early to reach the socket.
Future<void> _aWhile() =>
    Future<void>.delayed(const Duration(milliseconds: 250));

List<String> _marks(FakeKoboldEngine engine, List<String> marks) => [
  for (final r in engine.arrived)
    marks.firstWhere(r.promptText.contains, orElse: () => '?'),
];

void main() {
  late KoboldEngineHarness h;
  late Completer<void> hold;

  setUp(() async {
    h = await KoboldEngineHarness.start();
    hold = Completer<void>();
    // Whatever mentions FIRST stays in the engine until the test lets go.
    h.engine.beforeReply = (r) =>
        r.promptText.contains('FIRST') ? hold.future : Future<void>.value();
  });

  tearDown(() async {
    if (!hold.isCompleted) hold.complete();
    await h.dispose();
  });

  test('a second reply is not sent while the first is still going', () async {
    final first = h.kobold.generateStream(_ask('FIRST')).toList();
    await _until(() => h.engine.arrived.length == 1);

    final second = h.kobold.generateStream(_ask('SECOND')).toList();
    await _aWhile();
    expect(
      h.engine.arrived,
      hasLength(1),
      reason: 'the second reply reached the engine while the first was open',
    );

    hold.complete();
    await Future.wait([first, second]);
    expect(_marks(h.engine, ['FIRST', 'SECOND']), ['FIRST', 'SECOND']);
    expect(h.engine.maxInFlight, 1);
  });

  test('replies and tool calls keep the order they were asked in', () async {
    final a = h.kobold.generateStream(_ask('FIRST')).toList();
    await _until(() => h.engine.arrived.length == 1);

    // One ask per turn of the event loop: a stream takes its place when it
    // is listened to, a moment after a tool call takes its own.
    final b = h.kobold.generateWithTools(_ask('SECOND'), _tools);
    await _nextTurn();
    final c = h.kobold.generateStream(_ask('THIRD')).toList();
    await _nextTurn();
    final d = h.kobold.generateWithTools(_ask('FOURTH'), _tools);
    await _aWhile();
    expect(h.engine.arrived, hasLength(1));

    hold.complete();
    await Future.wait([a, b, c, d]);
    expect(_marks(h.engine, ['FIRST', 'SECOND', 'THIRD', 'FOURTH']), [
      'FIRST',
      'SECOND',
      'THIRD',
      'FOURTH',
    ]);
    expect(h.engine.maxInFlight, 1);
  });

  test('the system-role check takes its turn like any other request', () async {
    // The check's three requests are the third kind that reaches the cache.
    h.probe.resetForTest();
    h.engine.beforeReply = (r) =>
        h.engine.arrived.length <= 1 ? hold.future : Future<void>.value();
    final checking = h.kobold.debugMarkModelReady();
    await _until(() => h.engine.arrived.length == 1);

    final reply = h.kobold.generateStream(_ask('SECOND')).toList();
    await _aWhile();
    expect(
      h.engine.arrived,
      hasLength(1),
      reason: 'a reply was sent in the middle of the system-role check',
    );

    hold.complete();
    await Future.wait([checking, reply]);
    expect(h.engine.maxInFlight, 1);
    // The check goes one request at a time, so the reply asked while its
    // first request ran comes next, ahead of the check's later ones.
    expect(h.engine.arrived[1].promptText, contains('SECOND'));
  });

  test('a reply the reader walks away from hands the engine on', () async {
    h.engine.tokenDelay = const Duration(milliseconds: 40);
    hold.complete();
    final gotOne = Completer<void>();
    final sub = h.kobold.generateStream(_ask('FIRST')).listen((_) {
      if (!gotOne.isCompleted) gotOne.complete();
    });
    await gotOne.future;
    final second = h.kobold.generateStream(_ask('SECOND')).toList();

    await sub.cancel();

    await second.timeout(
      const Duration(seconds: 10),
      onTimeout: () => fail('the second reply never went out'),
    );
    expect(h.engine.of('chat').last.promptText, contains('SECOND'));
  });

  test('a reply that fails hands the engine on', () async {
    h.engine.chatStatusFor = (prompt) => prompt.contains('FIRST') ? 500 : null;
    final first = h.kobold.generateStream(_ask('FIRST')).toList();
    final second = h.kobold.generateStream(_ask('SECOND')).toList();

    await expectLater(first, throwsException);
    await second.timeout(
      const Duration(seconds: 10),
      onTimeout: () => fail('the second reply never went out'),
    );
    expect(h.engine.of('chat').last.promptText, contains('SECOND'));
  });

  test('a reply given up on and aborted while it waits hands on', () async {
    // What Stop and the eval engine's hang guard do: leave, then abort.
    final sub = h.kobold
        .generateStream(_ask('FIRST'))
        .listen((_) {}, onError: (_) {});
    await _until(() => h.engine.arrived.length == 1);
    final second = h.kobold.generateStream(_ask('SECOND')).toList();

    final left = sub.cancel().then((_) {}, onError: (_) {});
    h.kobold.abortGeneration();
    hold.complete();
    await left;

    await second.timeout(
      const Duration(seconds: 10),
      onTimeout: () => fail('the line was never handed on after the abort'),
    );
    expect(h.engine.of('chat').last.promptText, contains('SECOND'));
  });

  test(
    'waitForIdle waits for what is queued now, not for later arrivals',
    () async {
      final first = h.kobold.generateStream(_ask('FIRST')).toList();
      await _until(() => h.engine.arrived.length == 1);

      var idle = false;
      unawaited(h.kobold.waitForIdle().then((_) => idle = true));
      await _aWhile();
      expect(idle, isFalse, reason: 'the first reply is still going');

      final later = h.kobold.generateStream(_ask('SECOND')).toList();
      hold.complete();
      await first;
      await _until(() => idle);
      await later;
      await h.kobold.waitForIdle();
    },
  );
}
