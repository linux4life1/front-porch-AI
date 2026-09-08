// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:front_porch_ai/ui/chat_components/chat_components.dart';
import 'package:front_porch_ai/ui/chat_components/bubbles/theme_border_resolver.dart';
import 'package:front_porch_ai/ui/dialogs/ui_settings_dialog.dart';
import 'package:front_porch_ai/ui/waifu/waifu.dart';

import '../../golden/support/fakes.dart';
import '../../golden/support/fakes_storage.dart';

class _RecordingChat extends FakeChatService {
  ChatThemeOverrides _theme = ChatThemeOverrides();

  @override
  ChatThemeOverrides get sessionThemeOverrides => _theme;

  @override
  set sessionThemeOverrides(ChatThemeOverrides value) => _theme = value;
}

class _ThemeStorage extends FakeStorageService {
  @override
  Color getUserBubbleColor([
    CharacterCard? character,
    ChatThemePreset? themePreset,
    ChatThemeOverrides? themeOverrides,
  ]) {
    if (themePreset != null) {
      return themeOverrides?.userBubbleColor != null
          ? themeOverrides!.resolvedUserBubbleColor(themePreset)
          : themePreset.defaultUserBubbleColor;
    }
    return globalUserBubbleColor;
  }

  @override
  Color getUserTextColor([
    CharacterCard? character,
    ChatThemePreset? themePreset,
    ChatThemeOverrides? themeOverrides,
  ]) {
    if (themePreset != null) {
      return themeOverrides?.userTextColor != null
          ? themeOverrides!.resolvedUserTextColor(themePreset)
          : themePreset.defaultUserTextColor;
    }
    return globalUserTextColor;
  }

  @override
  Color getAiBubbleColor([
    CharacterCard? character,
    ChatThemePreset? themePreset,
    ChatThemeOverrides? themeOverrides,
  ]) {
    if (themePreset != null) {
      return themeOverrides?.aiBubbleColor != null
          ? themeOverrides!.resolvedAiBubbleColor(themePreset)
          : themePreset.defaultAiBubbleColor;
    }
    return globalAiBubbleColor;
  }

  @override
  Color getAiTextColor([
    CharacterCard? character,
    ChatThemePreset? themePreset,
    ChatThemeOverrides? themeOverrides,
  ]) {
    if (themePreset != null) {
      return themeOverrides?.aiTextColor != null
          ? themeOverrides!.resolvedAiTextColor(themePreset)
          : themePreset.defaultAiTextColor;
    }
    return globalAiTextColor;
  }

  @override
  Color getDialogueColor([
    CharacterCard? character,
    ChatThemePreset? themePreset,
    ChatThemeOverrides? themeOverrides,
  ]) {
    if (themePreset != null) {
      return themeOverrides?.dialogueColor != null
          ? themeOverrides!.resolvedDialogueColor(themePreset)
          : themePreset.defaultDialogueColor;
    }
    return globalDialogueColor;
  }

  @override
  Color getActionColor([
    CharacterCard? character,
    ChatThemePreset? themePreset,
    ChatThemeOverrides? themeOverrides,
  ]) {
    if (themePreset != null) {
      return themeOverrides?.actionColor != null
          ? themeOverrides!.resolvedActionColor(themePreset)
          : themePreset.defaultActionColor;
    }
    return globalActionColor;
  }

  @override
  String getChatFontFamily([
    CharacterCard? character,
    ChatThemePreset? themePreset,
    ChatThemeOverrides? themeOverrides,
  ]) => themePreset?.defaultFontFamily ?? 'sans-serif';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('resolver uses explicit overrides when chatService is null', () {
    final storage = _ThemeStorage();
    addTearDown(storage.dispose);
    final theme = ThemeBorderResolver.resolve(
      chatService: null,
      storage: storage,
      character: null,
      isUser: true,
      isDirectorNote: false,
      themeOverrides: ChatThemeOverrides(themeId: 'sakura'),
    );
    expect(theme.preset?.id, 'sakura');
    expect(theme.textColor, ChatThemePreset.sakura.defaultUserTextColor);
  });

  testWidgets(
    'Waifu UI settings write the theme onto the session, not ChatService',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(700, 1250));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final storage = FakeStorageService();
      final chat = _RecordingChat()
        ..sessionThemeOverrides = ChatThemeOverrides(themeId: 'galactic');
      addTearDown(storage.dispose);
      addTearDown(chat.dispose);

      ChatThemeOverrides? written;
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<StorageService>.value(value: storage),
            ChangeNotifierProvider<ChatService>.value(value: chat),
          ],
          child: MaterialApp(
            home: Material(
              child: UiSettingsDialog(
                character: CharacterCard(name: 'Iris'),
                themeOverrides: ChatThemeOverrides(),
                onThemeOverrides: (next) => written = next,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Sakura'));
      await tester.pump();

      expect(written?.themeId, 'sakura');
      expect(chat.sessionThemeOverrides.themeId, 'galactic');
    },
  );

  testWidgets(
    'ChatMessageList paints the passed session theme, not ChatService',
    (tester) async {
      final storage = _ThemeStorage();
      final chat = _RecordingChat()
        ..sessionThemeOverrides = ChatThemeOverrides(themeId: 'galactic');
      addTearDown(storage.dispose);
      addTearDown(chat.dispose);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<StorageService>.value(value: storage),
            ChangeNotifierProvider<ChatService>.value(value: chat),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: ChatMessageList(
                messages: [
                  ChatMessage(text: 'hi', sender: 'You', isUser: true),
                ],
                resolveSpeaker: (_) => (null, null),
                themeOverrides: ChatThemeOverrides(themeId: 'sakura'),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final want = ChatThemePreset.sakura.defaultUserBubbleColor.withValues(
        alpha: storage.bubbleOpacity,
      );
      final galactic = ChatThemePreset.galactic.defaultUserBubbleColor
          .withValues(alpha: storage.bubbleOpacity);
      expect(
        find.byWidgetPredicate((w) {
          if (w is! DecoratedBox) return false;
          final d = w.decoration;
          if (d is! BoxDecoration) return false;
          return d.color == want;
        }),
        findsWidgets,
      );
      expect(
        find.byWidgetPredicate((w) {
          if (w is! DecoratedBox) return false;
          final d = w.decoration;
          if (d is! BoxDecoration) return false;
          return d.color == galactic;
        }),
        findsNothing,
      );
    },
  );

  testWidgets('WaifuTranscript paints the session theme, not ChatService', (
    tester,
  ) async {
    final storage = _ThemeStorage();
    final chat = _RecordingChat()
      ..sessionThemeOverrides = ChatThemeOverrides(themeId: 'galactic');
    addTearDown(storage.dispose);
    addTearDown(chat.dispose);

    final session = WaifuSession(
      folderRoot: 'Kabbage',
      coworker: CharacterCard(name: 'Iris'),
      themeOverrides: ChatThemeOverrides(themeId: 'sakura'),
    )..transcript.add(const WaifuMessage(isUser: true, text: 'hi'));

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<StorageService>.value(value: storage),
          ChangeNotifierProvider<ChatService>.value(value: chat),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: WaifuTranscript(session: session, coworker: 'Iris'),
          ),
        ),
      ),
    );
    await tester.pump();

    final want = ChatThemePreset.sakura.defaultUserBubbleColor.withValues(
      alpha: storage.bubbleOpacity,
    );
    final galactic = ChatThemePreset.galactic.defaultUserBubbleColor.withValues(
      alpha: storage.bubbleOpacity,
    );
    expect(
      find.byWidgetPredicate((w) {
        if (w is! DecoratedBox) return false;
        final d = w.decoration;
        if (d is! BoxDecoration) return false;
        return d.color == want;
      }),
      findsWidgets,
    );
    expect(
      find.byWidgetPredicate((w) {
        if (w is! DecoratedBox) return false;
        final d = w.decoration;
        if (d is! BoxDecoration) return false;
        return d.color == galactic;
      }),
      findsNothing,
    );
  });
}
