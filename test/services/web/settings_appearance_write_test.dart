// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The Appearance tab's write half. Each key mirrors a desktop control; an
// unknown value is ignored, never stored (an older phone may send one this
// build does not know), and the resets clear only what the desktop's own
// buttons clear.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/web/facade/settings/settings.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';

import '../../golden/support/creator_test_support.dart';
import '../../golden/support/fakes.dart';

/// The writer's backend branches read the remote lane; the shared fake
/// leaves it out, so give this test a real (unconfigured) service.
class _FakeLlm extends FakeLLMProvider {
  final OpenRouterService remote = OpenRouterService();

  @override
  OpenRouterService get openRouterService => remote;
}

Future<StorageService> _storage() async {
  setupPathProviderMock();
  return makeGoldenStorage();
}

void main() {
  test('theme, font and corners follow only keys this build knows', () async {
    final storage = await _storage();
    final a = storage.appearance;

    await applyAppearanceWrite(storage, {'themeId': 'harbor'});
    expect(a.theme, AppThemeId.harbor);

    await applyAppearanceWrite(storage, {'themeId': 'not-a-theme'});
    expect(a.theme, AppThemeId.harbor, reason: 'an unknown id is ignored');

    await applyAppearanceWrite(storage, {'uiFont': 'atkinson'});
    expect(a.font, UiFont.atkinson);

    // The stored key for the standard corners is 'default', not the enum's
    // name — a round trip that sent 'standard' must not be mistaken for it.
    await applyAppearanceWrite(storage, {'corners': 'round'});
    expect(a.corners, UiCorners.round);
    await applyAppearanceWrite(storage, {'corners': 'standard'});
    expect(a.corners, UiCorners.round, reason: 'not a key this build stores');
    await applyAppearanceWrite(storage, {'corners': 'default'});
    expect(a.corners, UiCorners.standard);
  });

  test('accent takes #RRGGBB and clears to the theme accent', () async {
    final storage = await _storage();
    final a = storage.appearance;

    await applyAppearanceWrite(storage, {'accent': '#2e7d32'});
    expect(a.accentOverride, const Color(0xFF2E7D32));

    await applyAppearanceWrite(storage, {'accent': ''});
    expect(a.accentOverride, isNull);

    await applyAppearanceWrite(storage, {'accent': '#2E7D32'});
    await applyAppearanceWrite(storage, {'accent': 'rgb(1,2,3)'});
    expect(a.accentOverride, isNull, reason: 'anything not hex is no accent');
  });

  test('the reset clears accent, font and corners, never the theme', () async {
    final storage = await _storage();
    final a = storage.appearance;
    await applyAppearanceWrite(storage, {
      'themeId': 'plum',
      'accent': '#2E7D32',
      'uiFont': 'literata',
      'corners': 'sharp',
    });

    await applyAppearanceWrite(storage, {'resetAppearance': true});
    expect(a.theme, AppThemeId.plum);
    expect(a.accentOverride, isNull);
    expect(a.font, UiFont.inter);
    expect(a.corners, UiCorners.standard);
  });

  test('chat font is gated to the shared catalog', () async {
    final storage = await _storage();
    final ui = storage.uiSettings;

    await applyAppearanceWrite(storage, {'chatFont': 'Fira Code'});
    expect(ui.globalChatFontFamily, 'Fira Code');

    await applyAppearanceWrite(storage, {'chatFont': 'Comic Sans'});
    expect(ui.globalChatFontFamily, 'Fira Code', reason: 'not in the catalog');

    await applyAppearanceWrite(storage, {'chatFont': ''});
    expect(ui.globalChatFontFamily, '');
  });

  test('chat colours write per row and reset to the theme', () async {
    final storage = await _storage();
    final ui = storage.uiSettings;
    final before = ui.globalAiBubbleColor;

    await applyAppearanceWrite(storage, {
      'chatColors': {'aiBubble': '#101010', 'dialogue': '#ff0000'},
    });
    expect(ui.globalAiBubbleColor, const Color(0xFF101010));
    expect(ui.globalDialogueColor, const Color(0xFFFF0000));

    await applyAppearanceWrite(storage, {'resetChatColors': true});
    expect(ui.globalAiBubbleColor, before);
    expect(ui.globalDialogueColor, storage.appearance.chatDefaults.dialogue);
  });

  test('a reset in the same body wins over the picks', () async {
    // The page posts the whole form; a reset button pressed after a pick
    // sends both. The reset is what the user saw last, so it wins.
    final storage = await _storage();
    await applyAppearanceWrite(storage, {
      'accent': '#2e7d32',
      'uiFont': 'literata',
      'corners': 'sharp',
      'resetAppearance': true,
    });
    expect(storage.appearance.accentOverride, isNull);
    expect(storage.appearance.font, UiFont.inter);
    expect(storage.appearance.corners, UiCorners.standard);

    final ui = storage.uiSettings;
    await applyAppearanceWrite(storage, {
      'chatColors': {'aiBubble': '#101010'},
      'resetChatColors': true,
    });
    expect(ui.globalAiBubbleColor, storage.appearance.chatDefaults.aiBubble);
  });

  test('a POST reaches the storage setters through SettingsWriter', () async {
    // The only route from /api/settings to the appearance branches: a dropped
    // or misspelled call site would compile and stay green.
    final storage = await _storage();
    final llm = _FakeLlm();
    final writer = SettingsWriter(
      storage,
      llm,
      SettingsReasoning(storage, llm),
    );

    await writer.update({'themeId': 'harbor', 'uiFont': 'atkinson'});
    expect(storage.appearance.theme, AppThemeId.harbor);
    expect(storage.appearance.font, UiFont.atkinson);
  });
}
