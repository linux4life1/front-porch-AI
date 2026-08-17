// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// TestChampion HOLD — pump the real StoopUploadPage Content step and lock
// Adult → Comments order + comments default OFF. A grep is not enough.

import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:provider/provider.dart";

import "package:front_porch_ai/models/models.dart";
import "package:front_porch_ai/providers/auth_state.dart";
import "package:front_porch_ai/ui/pages/repository/stoop_adult_lock_banner.dart";
import "package:front_porch_ai/ui/pages/repository/stoop_comments_switch.dart";
import "package:front_porch_ai/ui/pages/repository/stoop_completeness_panel.dart";
import "package:front_porch_ai/ui/pages/repository/stoop_standards.dart";
import "package:front_porch_ai/ui/pages/repository/stoop_upload_page.dart";

CharacterCard _card() => CharacterCard(
  name: "Misty",
  description: "A meteorologist who talks to clouds.",
  firstMessage: "Hello there.",
  personality: "cheerful",
  scenario: "A weather station at dusk.",
);

Future<void> _openContentStep(WidgetTester tester) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ChangeNotifierProvider<AuthState>(
      create: (_) => AuthState(),
      child: MaterialApp(
        home: StoopUploadPage(updateCharacter: _card(), updateStoopId: "card1"),
      ),
    ),
  );
  await tester.pumpAndSettle();

  // Update mode opens on Details. Advance to the real Content step.
  expect(find.text("Next"), findsOneWidget);
  await tester.tap(find.text("Next"));
  await tester.pumpAndSettle();

  expect(find.byKey(const ValueKey("content")), findsOneWidget);
}

void main() {
  testWidgets("Content step: Adult switch, then Comments switch, default OFF", (
    tester,
  ) async {
    await _openContentStep(tester);

    expect(find.byType(StoopAdultSwitch), findsOneWidget);
    expect(find.byType(StoopCommentsSwitch), findsOneWidget);
    expect(find.text("This content is NSFW (18+)"), findsOneWidget);
    expect(find.text("Allow discussion on this card"), findsOneWidget);

    final comments = tester.widget<StoopCommentsSwitch>(
      find.byType(StoopCommentsSwitch),
    );
    expect(comments.value, isFalse);

    final tiles = tester
        .widgetList<SwitchListTile>(find.byType(SwitchListTile))
        .toList();
    expect(tiles.length, greaterThanOrEqualTo(2));
    expect((tiles[0].title as Text).data, "This content is NSFW (18+)");
    expect((tiles[1].title as Text).data, "Allow discussion on this card");
    expect(tiles[1].value, isFalse);

    // Order in the tree: Comments is the next section widget after Adult.
    final sections = <Type>[];
    void walk(Element e) {
      final w = e.widget;
      if (w is StoopAdultSwitch ||
          w is StoopCommentsSwitch ||
          w is StoopStandardsCard ||
          w is StoopCompletenessPanel ||
          w is StoopAdultLockBanner) {
        sections.add(w.runtimeType);
      }
      e.visitChildren(walk);
    }

    tester.element(find.byKey(const ValueKey("content"))).visitChildren(walk);
    expect(sections, contains(StoopAdultSwitch));
    expect(sections, contains(StoopCommentsSwitch));
    final adultAt = sections.indexOf(StoopAdultSwitch);
    final commentsAt = sections.indexOf(StoopCommentsSwitch);
    expect(commentsAt, adultAt + 1);
  });
}
