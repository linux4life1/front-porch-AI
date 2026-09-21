// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Saved wiki library: unlimited add/remove, persist, reject unsafe URLs.
//
// Guard proven red: addSavedWikiUrl without parseWikiBaseUrl stored
// javascript:alert; missing persist left the list empty after load().

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/services/storage/settings/web_search_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late WebSearchSettings settings;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    settings = WebSearchSettings();
    settings.initializeBase(prefs, () {});
    await settings.load();
  });

  test('add persists canonical origins with no cap', () async {
    expect(
      await settings.addSavedWikiUrl(
        'https://bleach.fandom.com/wiki/Sōsuke_Aizen',
      ),
      isTrue,
    );
    expect(settings.savedWikiUrls, ['https://bleach.fandom.com']);
    expect(settings.wikiBaseUrl, 'https://bleach.fandom.com');

    expect(
      await settings.addSavedWikiUrl('https://onepunchman.fandom.com/'),
      isTrue,
    );
    expect(settings.savedWikiUrls, [
      'https://bleach.fandom.com',
      'https://onepunchman.fandom.com',
    ]);
    // First saved stays the default.
    expect(settings.wikiBaseUrl, 'https://bleach.fandom.com');

    final prefs = await SharedPreferences.getInstance();
    final reloaded = WebSearchSettings();
    reloaded.initializeBase(prefs, () {});
    await reloaded.load();
    expect(reloaded.savedWikiUrls, [
      'https://bleach.fandom.com',
      'https://onepunchman.fandom.com',
    ]);
  });

  test('remove drops the row and replaces the default', () async {
    await settings.addSavedWikiUrl('https://bleach.fandom.com/');
    await settings.addSavedWikiUrl('https://onepunchman.fandom.com/');
    await settings.removeSavedWikiUrl('https://bleach.fandom.com');
    expect(settings.savedWikiUrls, ['https://onepunchman.fandom.com']);
    expect(settings.wikiBaseUrl, 'https://onepunchman.fandom.com');
  });

  test('unsafe URLs are rejected', () async {
    expect(await settings.addSavedWikiUrl(''), isFalse);
    expect(await settings.addSavedWikiUrl('not a url'), isFalse);
    expect(await settings.addSavedWikiUrl('javascript:alert(1)'), isFalse);
    expect(await settings.addSavedWikiUrl('http://localhost/wiki'), isFalse);
    expect(settings.savedWikiUrls, isEmpty);
  });

  test('character default is 1:1 only; groups seed nothing', () async {
    await settings.setWikiUrlForCharacter(
      'Sophia',
      'https://bleach.fandom.com/wiki/Aizen',
    );
    expect(settings.wikiUrlForCharacter('Sophia'), 'https://bleach.fandom.com');
    expect(
      settings.wikiUrlToSeedForNewChat(isGroup: false, characterId: 'Sophia'),
      'https://bleach.fandom.com',
    );
    expect(
      settings.wikiUrlToSeedForNewChat(isGroup: true, characterId: 'Sophia'),
      isNull,
    );
  });

  test('legacy wiki_base_url joins the saved list on load', () async {
    SharedPreferences.setMockInitialValues({
      'wiki_base_url': 'https://bleach.fandom.com/wiki/Aizen',
    });
    final prefs = await SharedPreferences.getInstance();
    final migrated = WebSearchSettings();
    migrated.initializeBase(prefs, () {});
    await migrated.load();
    expect(migrated.wikiBaseUrl, 'https://bleach.fandom.com');
    expect(migrated.savedWikiUrls, ['https://bleach.fandom.com']);
  });
}
