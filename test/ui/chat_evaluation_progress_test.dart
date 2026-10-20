// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/storage/settings/ui_settings.dart';
import 'package:front_porch_ai/ui/chat_components/chat_components.dart';
import '../golden/support/fakes.dart';

class EvaluationChat extends FakeChatService {
  EvaluationChat() : super(verificationPass: 2, verificationMaxPasses: 3);
  bool evaluating = true;
  bool greeting = false;
  bool verifying = false;
  bool checking = false;
  int skips = 0;
  @override
  bool get isEvaluatingRealism => evaluating;
  @override
  bool get isProcessingGreeting => greeting;
  @override
  bool get isVerifyingRealism => verifying;
  @override
  bool get isCheckingCompletion => checking;
  @override
  void skipObjectiveCheck() {
    skips++;
  }
}

class EvaluationStorage extends ChangeNotifier implements StorageService {
  @override
  final uiSettings = UiSettings();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets(
    'production eval builder remembers view and keeps progress beside composer',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final storage = EvaluationStorage();
      storage.uiSettings.initializeBase(prefs, storage.notifyListeners);
      storage.uiSettings.load();
      final chat = EvaluationChat();
      addTearDown(chat.dispose);
      addTearDown(storage.dispose);
      var reads = 0;
      Future<void> render() => tester.pumpWidget(
        ChangeNotifierProvider<StorageService>.value(
          value: storage,
          child: MaterialApp(
            home: Scaffold(
              appBar: AppBar(title: const Text('Synthetic chat')),
              body: Stack(
                children: [
                  Column(
                    children: [
                      Expanded(
                        child: Center(
                          child: TextButton(
                            onPressed: () => reads++,
                            child: const Text('Read chat'),
                          ),
                        ),
                      ),
                      ChatEvaluationProgress(chatService: chat, inline: true),
                      const SizedBox(
                        height: 60,
                        child: TextField(
                          decoration: InputDecoration(labelText: 'Composer'),
                        ),
                      ),
                    ],
                  ),
                  ChatEvaluationProgress(chatService: chat),
                ],
              ),
            ),
          ),
        ),
      );
      await render();
      expect(find.byType(RealismProcessingOverlay), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(RealismProcessingOverlay),
          matching: find.text('Minimize evaluation'),
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Minimize evaluation'));
      await tester.pump();
      await tester.pump();
      expect(storage.uiSettings.evaluationMinimized, true);
      expect(find.byType(RealismProcessingOverlay), findsNothing);
      final bar = tester.getRect(find.byType(EvaluationProgressShell));
      final composer = tester.getRect(find.byType(TextField));
      expect(bar.bottom, lessThanOrEqualTo(composer.top));
      expect(bar.top, greaterThan(tester.getRect(find.byType(AppBar)).bottom));
      await tester.tap(find.text('Read chat'));
      expect(reads, 1);
      final reload = UiSettings()
        ..initializeBase(prefs, () {})
        ..load();
      expect(reload.evaluationMinimized, true);
      final shell = tester.widget<EvaluationProgressShell>(
        find.byType(EvaluationProgressShell),
      );
      expect(shell.stopLabel, 'Stop this reply');
      expect(shell.onStop, isNotNull);
      await tester.pump(const Duration(seconds: 31));
      expect(find.text('31s elapsed'), findsOneWidget);
      chat.evaluating = false;
      await render();
      expect(find.byType(EvaluationProgressShell), findsNothing);
      chat.checking = true;
      await render();
      expect(find.text('Show evaluation details'), findsOneWidget);
      await tester.tap(find.text('Skip goal check'));
      expect(chat.skips, 1);
      chat.checking = false;
      chat.greeting = true;
      await render();
      expect(find.text('Reading the room…'), findsOneWidget);
      chat.greeting = false;
      chat.verifying = true;
      await render();
      expect(find.text('Verifying Realism output (pass 2/3)'), findsOneWidget);
      expect(find.text('Stop this reply'), findsNothing);
      await tester.tap(find.text('Show evaluation details'));
      await tester.pump();
      await tester.pump();
      expect(storage.uiSettings.evaluationMinimized, false);
      expect(find.byType(RealismProcessingOverlay), findsOneWidget);
      chat.verifying = false;
      chat.checking = true;
      await render();
      expect(find.byType(ObjectiveCheckOverlay), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(ObjectiveCheckOverlay),
          matching: find.text('Minimize evaluation'),
        ),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'eval overlays freeze the blur: no live BackdropFilter, still is the chat',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      const behind = Color(0xFFCC2020);
      final chat = EvaluationChat();
      addTearDown(chat.dispose);
      for (final overlay in <Widget>[
        RealismProcessingOverlay(chatService: chat, isGreeting: false),
        ObjectiveCheckOverlay(chatService: chat),
      ]) {
        await tester.pumpWidget(
          MaterialApp(
            home: RepaintBoundary(
              child: Stack(
                children: [
                  const Positioned.fill(child: ColoredBox(color: behind)),
                  overlay,
                ],
              ),
            ),
          ),
        );
        final root = find.byWidget(overlay);
        expect(
          find.descendant(of: root, matching: find.byType(BackdropFilter)),
          findsNothing,
        );
        final still = find.descendant(
          of: root,
          matching: find.byKey(FrozenBackdropBlur.stillKey),
        );
        expect(still, findsNothing);
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 200)),
        );
        await tester.pump(const Duration(milliseconds: 500));
        expect(still, findsOneWidget);
        expect(tester.getRect(still), tester.getRect(root));
        // The centre of the window is under the card; the still must hold
        // the chat behind it, not the card captured on top.
        final image = tester.widget<RawImage>(still).image!;
        final bytes = await tester.runAsync(
          () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
        );
        final at = ((image.height ~/ 2) * image.width + image.width ~/ 2) * 4;
        final rgba = bytes!.buffer.asUint8List(at, 4);
        expect(rgba[0], closeTo(0xCC, 6));
        expect(rgba[1], closeTo(0x20, 6));
        expect(rgba[2], closeTo(0x20, 6));
        await tester.pumpWidget(const SizedBox());
      }
    },
  );
}
