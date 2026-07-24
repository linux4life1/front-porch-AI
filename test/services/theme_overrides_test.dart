import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart';
import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/chat_theme_overrides.dart';
import 'package:front_porch_ai/models/chat_theme_preset.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        if (methodCall.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.path;
        }
        return null;
      });

  SharedPreferences.setMockInitialValues({});

  group('Database — theme_overrides column', () {
    late AppDatabase db;

    setUp(() async {
      db = AppDatabase.forTesting();
      await db.ensureSchemaIsRepaired();
    });

    tearDown(() async {
      await db.close();
    });

    test('defaults to null when session has no theme override', () async {
      final sessionId = 'theme-null-${DateTime.now().millisecondsSinceEpoch}';
      await db.insertSession(SessionsCompanion.insert(id: sessionId));

      final result = await db.getThemeOverrides(sessionId);
      expect(result, equals(null));
    });

    test('round-trips theme_overrides JSON', () async {
      final sessionId = 'theme-rt-${DateTime.now().millisecondsSinceEpoch}';
      await db.insertSession(SessionsCompanion.insert(id: sessionId));

      const themeJson = '{"themeId":"ocean","fontFamily":"serif"}';
      await db.setThemeOverrides(sessionId, themeJson);

      final result = await db.getThemeOverrides(sessionId);
      expect(result, themeJson);
    });

    test('can update existing theme_overrides', () async {
      final sessionId = 'theme-upd-${DateTime.now().millisecondsSinceEpoch}';
      await db.insertSession(SessionsCompanion.insert(id: sessionId));

      await db.setThemeOverrides(sessionId, '{"themeId":"ocean"}');
      await db.setThemeOverrides(
        sessionId,
        '{"themeId":"forest","userBubbleColor":"#1a1a2e"}',
      );

      final result = await db.getThemeOverrides(sessionId);
      final parsed = jsonDecode(result!) as Map<String, dynamic>;
      expect(parsed['themeId'], 'forest');
      expect(parsed['userBubbleColor'], '#1a1a2e');
    });

    test('can clear theme_overrides by setting to null', () async {
      final sessionId = 'theme-clr-${DateTime.now().millisecondsSinceEpoch}';
      await db.insertSession(SessionsCompanion.insert(id: sessionId));

      await db.setThemeOverrides(sessionId, '{"themeId":"ocean"}');
      await db.setThemeOverrides(sessionId, null);

      final result = await db.getThemeOverrides(sessionId);
      expect(result, equals(null));
    });

    test('retrieves last theme from previous sessions', () async {
      final base = 'theme-last-${DateTime.now().millisecondsSinceEpoch}';
      final charId = 'char-for-last-theme';

      final oldSessionId = '$base-old';
      await db.insertSession(
        SessionsCompanion.insert(
          id: oldSessionId,
          characterId: Value<String?>(charId),
        ),
      );
      await db.setThemeOverrides(oldSessionId, '{"themeId":"ocean"}');

      final newSessionId = '$base-new';
      await db.insertSession(
        SessionsCompanion.insert(
          id: newSessionId,
          characterId: Value<String?>(charId),
        ),
      );

      final inherited =
          await db.getLastSessionThemeOverrides(characterId: charId);
      expect(inherited, '{"themeId":"ocean"}');
    });
  });

  group('ChatThemeOverrides — dialogue/action fields', () {
    test('toJson/fromJson round-trips dialogueColor and actionColor', () {
      final overrides = ChatThemeOverrides(
        themeId: 'fantasy',
        dialogueColor: 'FFD54F',
        actionColor: 'A5D6A7',
      );
      final json = overrides.toJson();
      final restored = ChatThemeOverrides.fromJson(json);

      expect(restored.dialogueColor, 'FFD54F');
      expect(restored.actionColor, 'A5D6A7');
    });

    test('toJson omits null dialogue/action fields', () {
      final overrides = ChatThemeOverrides(themeId: 'noir');
      final json = overrides.toJson();
      expect(json.containsKey('dialogueColor'), isFalse);
      expect(json.containsKey('actionColor'), isFalse);
    });

    test('isCustomized returns true when only dialogueColor is set', () {
      final overrides = ChatThemeOverrides(
        themeId: 'fantasy',
        dialogueColor: 'FFD54F',
      );
      expect(overrides.isCustomized, isTrue);
    });

    test('resolvedDialogueColor falls back to preset default', () {
      final empty = ChatThemeOverrides(themeId: 'fantasy');
      final preset = ChatThemePreset.byId('fantasy')!;
      expect(empty.resolvedDialogueColor(preset), preset.defaultDialogueColor);
    });

    test('resolvedActionColor falls back to preset default', () {
      final empty = ChatThemeOverrides(themeId: 'steampunk');
      final preset = ChatThemePreset.byId('steampunk')!;
      expect(empty.resolvedActionColor(preset), preset.defaultActionColor);
    });

    test('resolvedDialogueColor uses override when set', () {
      final overrides = ChatThemeOverrides(
        themeId: 'fantasy',
        dialogueColor: 'FF0000',
      );
      final preset = ChatThemePreset.byId('fantasy')!;
      expect(
        overrides.resolvedDialogueColor(preset).toARGB32(),
        0xFFFF0000,
      );
    });

    test('malformed color string falls back to preset default (no throw)', () {
      // A corrupt/foreign override string (old export, hand-edited JSON, bad web
      // payload) must not crash message-bubble build — resolve to the preset
      // default instead. Covers every color channel that parses a stored hex.
      final preset = ChatThemePreset.byId('fantasy')!;
      final bad = ChatThemeOverrides(
        themeId: 'fantasy',
        userBubbleColor: 'zzzzzz',
        userTextColor: '#rgb',
        aiBubbleColor: '',
        aiTextColor: 'not-a-color',
        dialogueColor: 'GGGGGG',
        actionColor: 'nothex',
        borderColor: 'oops',
      );
      expect(bad.resolvedUserBubbleColor(preset), preset.defaultUserBubbleColor);
      expect(bad.resolvedUserTextColor(preset), preset.defaultUserTextColor);
      expect(bad.resolvedAiBubbleColor(preset), preset.defaultAiBubbleColor);
      expect(bad.resolvedAiTextColor(preset), preset.defaultAiTextColor);
      expect(bad.resolvedDialogueColor(preset), preset.defaultDialogueColor);
      expect(bad.resolvedActionColor(preset), preset.defaultActionColor);
      expect(bad.resolvedBorderColor(preset), preset.defaultBorderColor);
    });

    test('copy() preserves dialogue/action fields', () {
      final overrides = ChatThemeOverrides(
        themeId: 'galactic',
        dialogueColor: '80DEEA',
        actionColor: '7C4DFF',
      );
      final copy = overrides.copy();
      expect(copy.dialogueColor, '80DEEA');
      expect(copy.actionColor, '7C4DFF');
    });

    test('fromJsonString round-trips with dialogue/action', () {
      final overrides = ChatThemeOverrides(
        themeId: 'cyberpunk',
        dialogueColor: '00FF41',
        actionColor: 'FF00FF',
      );
      final str = overrides.toJsonString();
      final restored = ChatThemeOverrides.fromJsonString(str);
      expect(restored.dialogueColor, '00FF41');
      expect(restored.actionColor, 'FF00FF');
    });

    test('every preset has dialogue and action colors', () {
      for (final preset in ChatThemePreset.presets) {
        expect(preset.defaultDialogueColor.toARGB32(), isNot(0));
        expect(preset.defaultActionColor.toARGB32(), isNot(0));
      }
    });
  });
}
