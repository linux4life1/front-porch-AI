// Stop pressed while a chat reply is still waiting for the engine behind a
// request of an earlier turn (a journal or growth pass that outlived its
// turn). The Stop button sets the turn's cancel flag and aborts the lanes; it
// does not cancel the reader's subscription, so the reply has to look at the
// flag itself. Each test presses the real Stop on a real ChatService.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

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
}
