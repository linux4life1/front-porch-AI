// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Enhance Review says "New lorebook entries" — Save must append those
// onto the book duplicateCharacter just copied, never replace it.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chargen/chargen.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/pages/home/enhance/enhance_review_body.dart';

class _Repo extends Fake implements CharacterRepository {
  CharacterCard? lastUpdated;

  @override
  Future<CharacterCard?> duplicateCharacter(
    CharacterCard card, {
    String? targetDirOverride,
    String? forcedBasename,
    bool skipLibraryInsert = false,
    String? newNameOverride,
  }) async {
    return CharacterCard(
      name: newNameOverride ?? '${card.name} (duplicate)',
      description: card.description,
      lorebook: card.lorebook != null
          ? Lorebook(entries: List.of(card.lorebook!.entries))
          : null,
    );
  }

  @override
  Future<void> updateCharacter(CharacterCard card, {bool notify = true}) async {
    lastUpdated = card;
  }
}

class _Folders extends Fake implements FolderService {
  @override
  Future<void> inheritFolder(String? sourcePath, String? copyPath) async {}
}

void main() {
  test('mergeLorebookEntries appends and replaces by name', () {
    final original = [
      LorebookEntry(name: 'The Kitchen', content: 'original kitchen'),
      LorebookEntry(name: 'The Porch', content: 'original porch'),
    ];
    final incoming = [
      LorebookEntry(name: 'The Bar', content: 'new bar'),
      LorebookEntry(name: 'The Kitchen', content: 'rewritten kitchen'),
    ];
    final merged = mergeLorebookEntries(original, incoming);
    expect(merged.map((e) => e.name), ['The Kitchen', 'The Porch', 'The Bar']);
    expect(merged[0].content, 'rewritten kitchen');
    expect(merged[1].content, 'original porch');
    expect(merged[2].content, 'new bar');
  });

  testWidgets('Save appends accepted lore onto the duplicated original book', (
    tester,
  ) async {
    final repo = _Repo();
    final original = CharacterCard(
      name: 'Nina',
      lorebook: Lorebook(
        entries: [LorebookEntry(name: 'The Kitchen', content: 'kept')],
      ),
    );
    final enhanced = CharacterCard(
      name: 'Nina',
      lorebook: Lorebook(
        entries: [LorebookEntry(name: 'The Bar', content: 'new place')],
      ),
    );
    final key = GlobalKey<EnhanceReviewBodyState>();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<CharacterRepository>.value(value: repo),
          Provider<FolderService>.value(value: _Folders()),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: EnhanceReviewBody(
              key: key,
              original: original,
              enhanced: enhanced,
              selection: const EnhanceSelection(
                description: false,
                personality: false,
                exampleDialogue: false,
                lorebook: true,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final saved = await key.currentState!.save();
    expect(saved, isNotNull);
    final names = repo.lastUpdated!.lorebook!.entries.map((e) => e.name);
    expect(names, ['The Kitchen', 'The Bar']);
    expect(repo.lastUpdated!.lorebook!.entries[0].content, 'kept');
    expect(repo.lastUpdated!.lorebook!.entries[1].content, 'new place');
  });
}
