// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Reading size is one pref and one MediaQuery scaler. Bubbles used to
// multiply StorageService.textScale on top of that scaler, so chat text
// jumped while the composer and the edit overlay stayed small.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/chat_components/chat_components.dart';
import 'package:front_porch_ai/ui/dialogs/dialogs.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

import '../../golden/support/fakes_storage.dart';

class _ReadingStorage extends FakeStorageService {
  _ReadingStorage(this.scale) {
    uiSettings.setTextScale(scale);
  }
  final double scale;
}

double _declaredFontSize(TextStyle? style) {
  final size = style?.fontSize;
  expect(
    size,
    isNotNull,
    reason: 'reading surface must set an explicit fontSize',
  );
  return size!;
}

double _scalerOf(Element element) =>
    MediaQuery.textScalerOf(element).scale(1.0);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'at textScale 1.5, bubble, composer, and edit field move together without double-applying on bubbles',
    (tester) async {
      const scale = 1.5;
      final storage = _ReadingStorage(scale);
      final composer = TextEditingController(text: 'Hello composer');
      addTearDown(composer.dispose);

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: ChangeNotifierProvider<StorageService>.value(
            value: storage,
            child: MaterialApp(
              home: Scaffold(
                body: Column(
                  children: [
                    const StyledChatMessage(
                      text: '"Hello," she said.',
                      isUser: true,
                    ),
                    AppTextField(
                      key: const Key('composer'),
                      controller: composer,
                      style: readingSurfaceStyle(color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final bubbleText = tester.widget<RichText>(find.byType(RichText).first);
      final bubbleSize = _declaredFontSize((bubbleText.text as TextSpan).style);
      final bubbleElement = tester.element(find.byType(RichText).first);
      final bubbleScale = _scalerOf(bubbleElement);

      final composerField = tester.widget<EditableText>(
        find.descendant(
          of: find.byKey(const Key('composer')),
          matching: find.byType(EditableText),
        ),
      );
      final composerSize = _declaredFontSize(composerField.style);
      final composerScale = _scalerOf(
        tester.element(find.byType(EditableText).first),
      );

      // Declared size is the shared base — not 14 * 1.5 = 21, which is the
      // double-apply that made bubbles jump while everything else lagged.
      expect(bubbleSize, kReadingFontSize);
      expect(composerSize, kReadingFontSize);
      expect(bubbleScale, scale);
      expect(composerScale, scale);
      expect(bubbleSize * bubbleScale, kReadingFontSize * scale);
      expect(composerSize * composerScale, bubbleSize * bubbleScale);

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: ChangeNotifierProvider<StorageService>.value(
            value: storage,
            child: MaterialApp(
              home: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () {
                    showMessageEditDialog(
                      context: context,
                      initialText: 'Hello edit',
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      final editFields = find.byType(AppTextField);
      expect(editFields, findsWidgets);
      final bodyField = tester.widget<EditableText>(
        find.descendant(
          of: editFields.last,
          matching: find.byType(EditableText),
        ),
      );
      final editSize = _declaredFontSize(bodyField.style);
      final editScale = _scalerOf(
        tester.element(
          find.descendant(
            of: editFields.last,
            matching: find.byType(EditableText),
          ),
        ),
      );
      expect(editSize, kReadingFontSize);
      expect(editScale, scale);
      expect(editSize * editScale, bubbleSize * bubbleScale);
    },
  );

  testWidgets(
    'edit dialog re-applies the house scaler when the overlay drops it',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (outer) {
              return MediaQuery(
                data: MediaQuery.of(
                  outer,
                ).copyWith(textScaler: const TextScaler.linear(1.5)),
                // Inner context is what a chat bubble would have — the house
                // scaler lives on `home:`, not on the navigator overlay.
                child: Builder(
                  builder: (context) {
                    return ElevatedButton(
                      onPressed: () {
                        showMessageEditDialog(
                          context: context,
                          initialText: 'Hello edit',
                        );
                      },
                      child: const Text('Open'),
                    );
                  },
                ),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      final body = find.descendant(
        of: find.byType(AppTextField).last,
        matching: find.byType(EditableText),
      );
      expect(_scalerOf(tester.element(body)), 1.5);
      final style = tester.widget<EditableText>(body).style;
      expect(_declaredFontSize(style) * 1.5, kReadingFontSize * 1.5);
    },
  );

  // The first test only checked MediaQuery on the element. Flutter's
  // RichText defaults to TextScaler.noScaling and does NOT read that
  // ancestor — which is why Reading Size 2.00 left quoted / *action*
  // bubbles at 14px after we stopped multiplying fontSize ourselves.
  testWidgets(
    'quoted and action bubbles pass the house scaler into RichText, not noScaling',
    (tester) async {
      const scale = 1.5;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: ChangeNotifierProvider<StorageService>.value(
            value: _ReadingStorage(scale),
            child: const MaterialApp(
              home: Scaffold(
                body: StyledChatMessage(
                  text: '"Hello," she said. *winks*',
                  isUser: true,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final richTexts = tester.widgetList<RichText>(find.byType(RichText));
      expect(
        richTexts,
        isNotEmpty,
        reason: 'dialogue/action path uses RichText',
      );
      for (final rt in richTexts) {
        expect(
          rt.textScaler.scale(1.0),
          scale,
          reason:
              'RichText defaults to TextScaler.noScaling. Ambient MediaQuery '
              'is not enough — the widget must pass the house scaler.',
        );
      }
    },
  );

  // Live report: slider at 2.00 scaled chrome / composer / chips, not the
  // bubble body. Ambient MediaQuery in that tree can sit at 1.0 (or the
  // 1280px responsive scaler) while StorageService.textScale is 2.0.
  // Bubbles must follow the pref, not the ancestor.
  testWidgets(
    'quoted bubbles follow StorageService.textScale even when ambient MediaQuery is 1.0',
    (tester) async {
      const scale = 2.0;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.0)),
          child: ChangeNotifierProvider<StorageService>.value(
            value: _ReadingStorage(scale),
            child: const MaterialApp(
              home: Scaffold(
                body: StyledChatMessage(
                  text: '"Hello," she said. *winks*',
                  isUser: true,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final richTexts = tester.widgetList<RichText>(find.byType(RichText));
      expect(richTexts, isNotEmpty);
      for (final rt in richTexts) {
        expect(
          rt.textScaler.scale(1.0),
          scale,
          reason:
              'Reading Size is StorageService.textScale. Ambient MediaQuery '
              'at 1.0 must not pin quoted / *action* bubbles at 14px.',
        );
      }
    },
  );

  testWidgets('composer follows Reading Size when ambient MediaQuery is 1.0', (
    tester,
  ) async {
    const scale = 2.0;
    final composer = TextEditingController(text: 'Hello composer');
    addTearDown(composer.dispose);
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.0)),
        child: ChangeNotifierProvider<StorageService>.value(
          value: _ReadingStorage(scale),
          child: MaterialApp(
            home: Scaffold(
              body: ReadingSizeScope(
                textScale: scale,
                child: AppTextField(
                  key: const Key('composer'),
                  controller: composer,
                  style: readingSurfaceStyle(color: Colors.white),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      _scalerOf(tester.element(find.byType(EditableText))),
      scale,
      reason:
          'TextField reads MediaQuery. Without ReadingSizeScope the '
          'composer stays 14px while the slider is at 2.00.',
    );
  });

  testWidgets(
    'edit dialog follows StorageService.textScale when ambient MediaQuery is 1.0',
    (tester) async {
      const scale = 2.0;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.0)),
          child: ChangeNotifierProvider<StorageService>.value(
            value: _ReadingStorage(scale),
            child: MaterialApp(
              home: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () {
                    showMessageEditDialog(
                      context: context,
                      initialText: 'Hello edit',
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      final body = find.descendant(
        of: find.byType(AppTextField).last,
        matching: find.byType(EditableText),
      );
      expect(_scalerOf(tester.element(body)), scale);
    },
  );
}
