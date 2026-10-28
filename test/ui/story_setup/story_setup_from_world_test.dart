// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

// Stories set in Worlds, slice 5 (docs/design/stories-in-worlds.md §3.4):
// New Story opened from a world card ("Write a story here") starts on Idea
// with that world already on the card and in the rail.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/pages/story_setup_page.dart';
import 'package:front_porch_ai/ui/story_studio/story_world_lookup.dart';

import '../../golden/support/fakes.dart';
import '../../golden/support/fakes_storage.dart';

/// In-memory shelf; nothing is written anywhere.
class _ShelfRepository extends ChangeNotifier implements StoryRepository {
  @override
  final List<StoryProject> projects = [];
  @override
  StoryProject? getById(String id) =>
      projects.where((p) => p.dbId == id).firstOrNull;
  @override
  Future<void> saveProject(StoryProject project) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The rail lists local model files and presets; point both folders somewhere
/// empty so the labels read "no model picked".
class _NoModelsStorage extends FakeStorageService {
  final Directory _empty = Directory(
    p.join(Directory.systemTemp.path, 'fpai_story_from_world_no_models'),
  );
  @override
  Directory get modelsDir => _empty;
  @override
  Directory get binDir => _empty;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('New Story from a world opens on Idea with the world picked', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repo = _ShelfRepository();
    final storage = _NoModelsStorage();
    final llm = FakeLLMProvider();
    final chars = FakeCharacterRepository();
    final persona = FakeUserPersonaService();
    addTearDown(repo.dispose);
    addTearDown(storage.dispose);
    addTearDown(llm.dispose);
    addTearDown(chars.dispose);
    addTearDown(persona.dispose);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<StoryRepository>.value(value: repo),
          ChangeNotifierProvider<CharacterRepository>.value(value: chars),
          ChangeNotifierProvider<UserPersonaService>.value(value: persona),
          ChangeNotifierProvider<StorageService>.value(value: storage),
          ChangeNotifierProvider<LLMProvider>.value(value: llm),
        ],
        child: const MaterialApp(
          home: StorySetupPage(
            fromWorld: StoryWorldPick(
              placeId: 'conservatory',
              worldName: 'Greenhollow Estate',
              detail: 'starts at The Conservatory · 3 places · 11 facts',
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('story-world-card')), findsOneWidget);
    expect(find.text('Greenhollow Estate'), findsWidgets);
    expect(
      find.text('starts at The Conservatory · 3 places · 11 facts'),
      findsWidgets,
    );
    expect(find.byKey(const ValueKey('story-change-world')), findsOneWidget);
    expect(find.byKey(const ValueKey('story-choose-world')), findsNothing);
  });
}
