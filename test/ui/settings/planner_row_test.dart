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

// Focused net: Porch Life / Presence has exactly one Planner row, default off.

import "dart:io";

import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";

import "package:front_porch_ai/ui/settings/widgets/feature_row.dart";
import "package:front_porch_ai/ui/widgets/planner_feature_row.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test("porch_life_tab places exactly one PlannerFeatureRow after Ambitions", () {
    final src = File("lib/ui/settings/tabs/porch_life_tab.dart").readAsStringSync();
    expect("PlannerFeatureRow(".allMatches(src).length, 1);
    expect(RegExp(r"label:\s*'Planner'").allMatches(src).length, 0);
    final presence = src.indexOf("title: 'Presence'");
    final ambitions = src.indexOf("label: 'Ambitions'");
    final planner = src.indexOf("PlannerFeatureRow(");
    final notice = src.indexOf("label: 'Notice new characters'");
    expect(presence, greaterThanOrEqualTo(0));
    expect(ambitions, greaterThan(presence));
    expect(planner, greaterThan(ambitions));
    expect(notice, greaterThan(planner));
  });

  testWidgets(
    "Porch Life Presence has exactly one Planner row, default off",
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FeatureGroupCard(
              title: "Presence",
              subtitle: "noticing you, nothing more",
              rows: [
                PlannerFeatureRow(onChanged: (_) {}),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text("Presence"), findsOneWidget);
      expect(find.text("Planner"), findsOneWidget);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    },
  );
}
