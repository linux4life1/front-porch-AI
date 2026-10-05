// While a reply waits because the preset editor's speed test has the engine,
// the status bar under the chat says so in plain words, as it does for a
// journal or growth pass.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/models/models.dart' show GenerationPhase;
import 'package:front_porch_ai/services/live_gen_progress.dart';
import 'package:front_porch_ai/ui/chat_components/chat_components.dart'
    show GenerationStatusBar;

import '../../golden/support/fakes.dart';

/// A reply that waits: nothing read yet, the engine held by [_live].
class _Waiting extends FakeChatService {
  _Waiting(this._live)
    : super(
        isGenerating: true,
        generationPhase: GenerationPhase.prefilling,
        prefillElapsedSeconds: 12,
        prefillMetricsAreMeasured: false,
      );

  final LiveGenProgress _live;

  @override
  LiveGenProgress? get activeLiveProgress => _live;
}

void main() {
  testWidgets('a reply waiting for the speed test says what it waits for', (
    tester,
  ) async {
    final chat = _Waiting(LiveGenProgress()..heldBy = 'the speed test');
    addTearDown(chat.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: GenerationStatusBar(chatService: chat)),
      ),
    );

    expect(
      find.text('Waiting — the speed test is using the model (12s)'),
      findsOneWidget,
    );
    // The bar ticks on a timer: take it down before the test ends.
    await tester.pumpWidget(const SizedBox());
  });
}
