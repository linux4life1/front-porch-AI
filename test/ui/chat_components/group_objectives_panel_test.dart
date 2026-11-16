// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// The group Objectives panel's load: only the newest read paints, a parent
// rebuild that hands over a new card instance for the same member does not
// strand the spinner, and a failed read shows the empty state.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/database/database.dart' show Objective;
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/ui/chat_components/sidebar/story_tools/story_tools.dart'
    show GroupObjectivesPanel;

import '../../golden/support/fakes.dart' show FakeChatService;

class _Chat extends FakeChatService {
  final reads = <String, Completer<List<Objective>>>{};
  int readCount = 0;

  @override
  Future<List<Objective>> getActiveObjectivesFor(CharacterCard character) {
    readCount++;
    return (reads[character.name] = Completer<List<Objective>>()).future;
  }
}

void main() {
  late _Chat chat;
  setUp(() => chat = _Chat());
  tearDown(() => chat.dispose());

  Future<void> pump(WidgetTester tester, CharacterCard member) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GroupObjectivesPanel(chatService: chat, member: member),
          ),
        ),
      );

  testWidgets('a new card instance for the same member does not strand the '
      'spinner', (tester) async {
    await pump(tester, CharacterCard(name: 'Ana'));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // The parent rebuilds with an equal-but-new instance mid-read.
    await pump(tester, CharacterCard(name: 'Ana'));
    chat.reads['Ana']!.complete(const []);
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.textContaining('No primary objective set'), findsOneWidget);
  });

  testWidgets('a failed read shows the empty state, not a spinner', (
    tester,
  ) async {
    await pump(tester, CharacterCard(name: 'Ana'));
    chat.reads['Ana']!.completeError(StateError('db closed'));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.textContaining('No primary objective set'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
