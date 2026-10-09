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

// Settings → Porch Life: "Temperatures in °F" hangs off Story Weather, which
// hangs off Passage of Time. With the clock off, Story Weather greys out even
// while its own switch is on, so °F must grey out with it.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/storage/settings/realism_settings.dart';
import 'package:front_porch_ai/ui/settings/tabs/porch_life_tab.dart';

import '../../golden/support/fakes.dart';
import '../../golden/support/fakes_storage.dart';

/// A [StorageService] double over a REAL [RealismSettings] (no prefs), so the
/// tab reads production defaults and setters notify like the app does.
class _PorchLifeStorage extends FakeStorageService {
  _PorchLifeStorage() {
    _realism.initializeBase(null, notifyListeners);
  }

  final RealismSettings _realism = RealismSettings();

  @override
  RealismSettings get realismSettings => _realism;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('°F greys out with the clock off, and comes back with it', (
    tester,
  ) async {
    // Tall enough that the Time & World card is on screen without scrolling.
    await tester.binding.setSurfaceSize(const Size(900, 2800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final storage = _PorchLifeStorage();
    final chat = FakeChatService();
    addTearDown(() {
      storage.dispose();
      chat.dispose();
    });

    await storage.realismSettings.setPassageOfTimeDefault(false);
    expect(storage.realismSettings.weatherEnabled, isTrue);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<StorageService>.value(value: storage),
          ChangeNotifierProvider<ChatService>.value(value: chat),
        ],
        child: const MaterialApp(home: Scaffold(body: PorchLifeTab())),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    Switch switchOf(String label) => tester.widget<Switch>(
      find
          .descendant(
            of: find
                .ancestor(of: find.text(label), matching: find.byType(Row))
                .first,
            matching: find.byType(Switch),
          )
          .first,
    );

    expect(
      switchOf('Story Weather').onChanged,
      isNull,
      reason: 'Story Weather is gated on the clock',
    );
    expect(
      switchOf('Temperatures in °F').onChanged,
      isNull,
      reason:
          'with Passage of Time off, Story Weather is greyed out, so °F '
          'must not stay clickable',
    );

    await storage.realismSettings.setPassageOfTimeDefault(true);
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      switchOf('Temperatures in °F').onChanged,
      isNotNull,
      reason: 'clock and weather both on: °F is live again',
    );
  });
}
