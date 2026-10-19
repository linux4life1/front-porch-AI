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

/// A reply reading its own prompt from [_live]: nothing holds the engine.
class _Reading extends FakeChatService {
  _Reading(this._live)
    : super(
        isGenerating: true,
        generationPhase: GenerationPhase.prefilling,
        prefillElapsedSeconds: 390,
        prefillMetricsAreMeasured: true,
        lastPerfData: const {'last_process_speed': 400.0},
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

  testWidgets('reading the prompt shows only counts the backend confirmed, '
      'with the estimate as time left', (tester) async {
    final now = DateTime.now();
    final live = LiveGenProgress()
      ..ingest(
        'Processing Prompt [BATCH] (8192 / 22124 tokens)',
        now: now.subtract(const Duration(seconds: 330)),
      )
      ..ingest(
        'Processing Prompt [BATCH] (16384 / 22124 tokens)',
        now: now.subtract(const Duration(seconds: 60)),
      );
    final chat = _Reading(live);
    addTearDown(chat.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: GenerationStatusBar(chatService: chat)),
      ),
    );

    // KoboldCpp printed 16,384 as batch two STARTED; 8,192 is what is read.
    expect(
      find.textContaining('Reading prompt — 8,192 / 22,124 tokens (37%) · ~'),
      findsOneWidget,
    );
    expect(find.textContaining('min left'), findsOneWidget);
    expect(find.textContaining('16,384'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
