// Stop pressed while a chat reply is still waiting for the engine behind a
// request of an earlier turn (a journal or growth pass that outlived its
// turn). The Stop button sets the turn's cancel flag and aborts the lanes; it
// does not cancel the reader's subscription, so the reply has to look at the
// flag itself, and the abort must not take the earlier turn's pass down with
// it. A character or group switch sets the same flag without aborting, and
// waits for the turn to end: the reply has to leave the line for it too. Each
// test presses the real Stop, or makes the real switch, on a real ChatService.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';

import '../../helpers/kobold_chat_harness.dart';

Future<void> _until(bool Function() done) async {
  final end = DateTime.now().add(const Duration(seconds: 10));
  while (!done()) {
    if (DateTime.now().isAfter(end)) fail('waited 10 s for something');
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

/// Long enough for a request sent too early to reach the socket.
Future<void> _aWhile() =>
    Future<void>.delayed(const Duration(milliseconds: 250));

/// A second lane whose abort reaches the same engine. The app wires a worker
/// on the same engine as the same service, so this is not how it runs; Stop
/// must not depend on that.
class _SameEngine extends LLMService {
  _SameEngine(this._kobold);

  final KoboldService _kobold;

  @override
  Stream<String> generateStream(GenerationParams params) =>
      _kobold.generateStream(params);

  @override
  void abortGeneration() => _kobold.abortGeneration();

  @override
  bool get isReady => _kobold.isReady;

  @override
  String get backendName => _kobold.backendName;
}

void main() {
  late KoboldChatHarness h;
  late Completer<void> hold;

  setUp(() async {
    h = await KoboldChatHarness.start();
    // A turn that was sent and answered: its chat is saved in a slot.
    await h.chat.sendMessage('Good evening, Ada.');
    await h.settle();
    h.engine.forgetLog();
    hold = Completer<void>();
    // An earlier turn's background pass holds the engine until the test
    // lets go of it.
    h.engine.beforeReply = (r) =>
        r.promptText.contains('EARLIER') ? hold.future : Future<void>.value();
    addTearDown(() {
      if (!hold.isCompleted) hold.complete();
    });
  });

  /// The pass of the earlier turn, in the line first and on the wire.
  Future<void> startEarlierPass() async {
    unawaited(
      h.kobold
          .generateStream(
            const GenerationParams(prompt: 'EARLIER pass words', maxLength: 16),
          )
          .toList()
          .then((_) {}, onError: (_) {}),
    );
    await _until(() => h.engine.arrived.length == 1);
  }

  Iterable<Object> repliesSent() => h.engine.arrived.where(
    (r) => r.kind == 'chat' && r.prompt.first == '<system>',
  );

  test('Stop while the reply waits behind another request: the reply is '
      'never sent, and nothing is saved', () async {
    await startEarlierPass();
    final sending = h.chat.sendMessage('Did the rain stop?');
    await _until(() => h.chat.isGenerating);
    await _aWhile(); // the reply is in line behind the pass

    h.chat.stopGeneration(); // the Stop button
    hold.complete(); // and the pass ends
    await sending.timeout(const Duration(seconds: 10));
    await h.settle();

    expect(
      repliesSent(),
      isEmpty,
      reason: 'a reply the user stopped was still sent to the engine',
    );
    expect(
      h.engine.arrived.map((r) => r.kind),
      ['chat'],
      reason:
          'only the earlier pass: no load, no reply, no save for a '
          'reply the user stopped',
    );
    expect(h.chat.isGenerating, isFalse);
  });

  test('Stop while the chat is being loaded back: the reply is not sent, '
      'and not saved', () async {
    // Something else ran in between, so the reply has to load its chat.
    await h.kobold
        .generateStream(const GenerationParams(prompt: 'a judge', maxLength: 8))
        .toList();
    h.engine.forgetLog();
    final loading = Completer<void>();
    h.engine.beforeAdmin = (r) =>
        r.kind == 'load' ? loading.future : Future<void>.value();

    final sending = h.chat.sendMessage('Did the rain stop?');
    await _until(() => h.engine.arrived.any((r) => r.kind == 'load'));
    h.chat.stopGeneration(); // while the cache is coming back
    loading.complete();
    await sending.timeout(const Duration(seconds: 10));
    await h.settle();

    expect(
      repliesSent(),
      isEmpty,
      reason: 'a reply stopped during the load was still sent',
    );
    expect(h.engine.arrived.map((r) => r.kind), isNot(contains('save')));
    expect(h.chat.isGenerating, isFalse);
  });

  test('Stop leaves the earlier turn\'s pass alone, and the chat is free at '
      'once', () async {
    // Kept, not swallowed: a pass that Stop killed throws here.
    final earlier = h.kobold
        .generateStream(
          const GenerationParams(prompt: 'EARLIER pass words', maxLength: 16),
        )
        .toList();
    await _until(() => h.engine.arrived.length == 1);
    final sending = h.chat.sendMessage('Did the rain stop?');
    await _until(() => h.kobold.debugRepliesWaiting == 1);

    h.chat.stopGeneration(); // the Stop button
    // The chat does not wait for the pass: it still holds the engine.
    await sending.timeout(const Duration(seconds: 5));
    expect(hold.isCompleted, isFalse);
    expect(h.chat.isGenerating, isFalse);
    expect(h.kobold.debugRepliesWaiting, 0);
    await _aWhile(); // time for an abort that was sent to arrive
    expect(
      h.engine.aborts,
      0,
      reason: 'Stop told the engine to abort a pass of an earlier turn',
    );

    hold.complete();
    expect(
      await earlier,
      isNotEmpty,
      reason: 'the pass was cut off: its caller never got its answer',
    );
    expect(h.engine.arrived.map((r) => r.kind), ['chat']);
  });

  test('Stop leaves the request ahead alone through a second lane over the '
      'same engine too', () async {
    h.chat.testWorkerLlmServiceOverride = _SameEngine(h.kobold);
    final earlier = h.kobold
        .generateStream(
          const GenerationParams(prompt: 'EARLIER pass words', maxLength: 16),
        )
        .toList();
    await _until(() => h.engine.arrived.length == 1);
    final sending = h.chat.sendMessage('Did the rain stop?');
    await _until(() => h.kobold.debugRepliesWaiting == 1);

    h.chat.stopGeneration(); // aborts the mouth, then the second lane
    await sending.timeout(const Duration(seconds: 5));
    await _aWhile(); // time for an abort that was sent to arrive

    expect(
      h.engine.aborts,
      0,
      reason: 'the second lane cut the pass of an earlier turn',
    );
    hold.complete();
    expect(
      await earlier,
      isNotEmpty,
      reason: 'the pass was cut off: its caller never got its answer',
    );
  });

  test('Stop while the reply is on the wire still cuts it and tells the '
      'engine', () async {
    final onTheWire = Completer<void>();
    h.engine.beforeReply = (r) =>
        r.promptText.contains('rain') ? onTheWire.future : Future<void>.value();
    addTearDown(() {
      if (!onTheWire.isCompleted) onTheWire.complete();
    });
    final sending = h.chat.sendMessage('Did the rain stop?');
    await _until(() => h.engine.arrived.any((r) => r.kind == 'chat'));

    h.chat.stopGeneration();
    await sending.timeout(const Duration(seconds: 5));
    await _aWhile();

    expect(
      h.engine.aborts,
      greaterThan(0),
      reason: 'nothing waited, so Stop had a reply on the wire to cut',
    );
    expect(h.chat.isGenerating, isFalse);
  });

  test('a character switch while a reply waits does not wait for the pass '
      'ahead of it', () async {
    final earlier = h.kobold
        .generateStream(
          const GenerationParams(prompt: 'EARLIER pass words', maxLength: 16),
        )
        .toList()
        .then((_) => 'ended', onError: (_) => 'ended');
    await _until(() => h.engine.arrived.length == 1);
    final sending = h.chat.sendMessage('Did the rain stop?');
    await _until(() => h.kobold.debugRepliesWaiting == 1);
    final bea = CharacterCard(
      name: 'Bea',
      description: 'Lives next door.',
      firstMessage: 'Hello.',
      imagePath: '/tmp/Bea-kobold-chat.png',
      frontPorchExtensions: FrontPorchExtensions(
        realismEnabled: false,
        needsSimEnabled: false,
      ),
    );
    await CharacterRepository(h.db, h.base.storage).addCharacter(bea);

    await h.chat
        .setActiveCharacter(bea)
        .timeout(
          const Duration(seconds: 5),
          onTimeout: () => fail('the switch waited for the pass ahead'),
        );

    expect(h.chat.activeCharacter?.name, 'Bea');
    expect(h.kobold.debugRepliesWaiting, 0);
    hold.complete();
    await earlier;
    await sending.timeout(const Duration(seconds: 5));
    expect(repliesSent(), isEmpty, reason: 'the reply was given up on');
  });

  test('opening the same chat again while a reply waits leaves the pass '
      'ahead alone', () async {
    // The switch to another character tears the lanes down afterwards, as it
    // always did; this way in stops after the wait, so what is left on the
    // wire is the drop's doing alone.
    final earlier = h.kobold
        .generateStream(
          const GenerationParams(prompt: 'EARLIER pass words', maxLength: 16),
        )
        .toList();
    await _until(() => h.engine.arrived.length == 1);
    final sending = h.chat.sendMessage('Did the rain stop?');
    await _until(() => h.kobold.debugRepliesWaiting == 1);

    await h.chat
        .setActiveCharacter(h.chat.activeCharacter)
        .timeout(
          const Duration(seconds: 5),
          onTimeout: () => fail('opening the chat waited for the pass ahead'),
        );

    expect(
      hold.isCompleted,
      isFalse,
      reason: 'the pass still holds the engine',
    );
    expect(h.kobold.debugRepliesWaiting, 0);
    await _aWhile(); // time for an abort that was sent to arrive
    expect(h.engine.aborts, 0, reason: 'a pass of an earlier turn was cut');
    hold.complete();
    expect(
      await earlier,
      isNotEmpty,
      reason: 'the pass was cut off: its caller never got its answer',
    );
    await sending.timeout(const Duration(seconds: 5));
    expect(repliesSent(), isEmpty, reason: 'the reply was given up on');
  });

  test('an abort that is not the Stop button cuts the wire even when a reply '
      'behind it has been given up on', () async {
    // What an eval does after an early answer, or a tool call after its
    // timeout: nobody pressed Stop, but the cancel flag of a character switch
    // may be set for the reply waiting behind.
    final earlier = h.kobold
        .generateStream(
          const GenerationParams(prompt: 'EARLIER pass words', maxLength: 16),
        )
        .toList()
        .then((_) => 'finished', onError: (_) => 'cut');
    await _until(() => h.engine.arrived.length == 1);
    var wanted = true;
    final reply = h.kobold
        .generateStream(
          GenerationParams(
            prompt: 'the reply words',
            maxLength: 16,
            kvChat: 'A',
            stillWant: () => wanted,
          ),
        )
        .toList();
    await _until(() => h.kobold.debugRepliesWaiting == 1);
    wanted = false;

    h.kobold.abortGeneration(); // the pass ends itself

    expect(
      await earlier.timeout(
        const Duration(seconds: 5),
        onTimeout: () => 'still running',
      ),
      'cut',
      reason: 'the abort was taken for the reply behind and the pass went on',
    );
    await _aWhile();
    expect(h.engine.aborts, 1, reason: 'the engine is told, as it always was');
    hold.complete();
    expect(await reply, isEmpty, reason: 'a reply given up on is never sent');
    expect(repliesSent(), isEmpty);
  });

  test('an abort that is not a Stop is as it was: it cuts the wire, and a '
      'reply waiting behind keeps its place', () async {
    final earlier = h.kobold
        .generateStream(
          const GenerationParams(prompt: 'EARLIER pass words', maxLength: 16),
        )
        .toList()
        .then((_) => 'finished', onError: (_) => 'cut');
    await _until(() => h.engine.arrived.length == 1);
    final sending = h.chat.sendMessage('Did the rain stop?');
    await _until(() => h.kobold.debugRepliesWaiting == 1);

    // What an eval does after an early answer: not the Stop button, so the
    // reply has not been given up on.
    h.kobold.abortGeneration();

    expect(await earlier, 'cut');
    hold.complete();
    await sending.timeout(const Duration(seconds: 10));
    await h.settle();
    expect(repliesSent(), hasLength(1), reason: 'the reply kept its place');
  });
}
