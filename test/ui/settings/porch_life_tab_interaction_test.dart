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

// Porch Life tab interaction net — required by the provability rule BEFORE
// this tab is trusted. Nothing else in CI opens Settings' Porch Life tab or
// taps a single one of its switches.
//
// This tab exists to fix a specific bug (docs/design/feature-independence.md):
// these switches used to live nested inside General's "Realism Mode" card, so
// turning the Realism Engine OFF also hid switches for features that work
// fine without it (the welcome-back recap and Story Weather among them).
// Pins: every row is a reachable landmark; the rows the tab was built to
// rescue stay visible AND tappable with the engine off; real taps flip real
// storage flags; the "needs X" dependency chip and its unmet-dependency
// warning render; the away-threshold dropdown is gated on its own switch.
//
// Four rows (Realism Engine, Needs, Afterglow, Passage of Time) also call
// through to `extension ChatServiceControls on ChatService` methods in their
// onChanged. Those are Dart EXTENSION methods, resolved statically against
// ChatService's declared type and reaching into that class's own private
// fields (_nsfwService, _activeGroup, _timeService, ...) — no double from
// outside chat_service.dart's library can ever satisfy that, override or
// not, so tapping those four rows against ANY fake throws NoSuchMethodError
// by construction. This net exercises the rows whose onChanged calls
// only StorageService/RealismSettings, and still verifies the other four
// rows render with a live, reachable Switch.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/storage/settings/realism_settings.dart';
import 'package:front_porch_ai/ui/settings/tabs/porch_life_tab.dart';

import '../../golden/support/fakes.dart';
import '../../golden/support/fakes_storage.dart';

/// A [StorageService] double wired to a REAL [RealismSettings] instance
/// (SharedPreferences left null, so its `prefs?.setX(...)` writes are
/// harmless no-ops) rather than a hand-rolled set of booleans. This means
/// every flag the tab reads/writes keeps its true production default and
/// `RealismSettings.notify()` bridges straight back into this fake's own
/// [notifyListeners] — exactly the path `context.watch<StorageService>()`
/// reacts to in the real app.
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

  testWidgets(
    'every Porch Life row renders, survives Realism Engine OFF, and takes '
    'real taps',
    (tester) async {
      // Tall enough that the whole tab is reachable. This sweep hunts labels
      // with scrollUntilVisible, which travels ONE WAY, and Pin 3 deliberately
      // checks them out of top-to-bottom order ('Welcome-back recap' → 'Story
      // Weather' → …). That only ever worked because at 1400px everything from
      // 'Story Weather' down shared a viewport, so the "scroll" was a no-op.
      //
      // This tab exists to accumulate feature switches, so that accident was
      // going to fail whichever row was added next regardless of its merits —
      // Pockets & Wardrobe is simply the one that found it (2026-08-07).
      // Raising the surface restores the assumption the sweep was written
      // against instead of reshaping how it searches. No assertion changes.
      await tester.binding.setSurfaceSize(const Size(900, 2800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final storage = _PorchLifeStorage();
      final chat = FakeChatService();
      addTearDown(() {
        storage.dispose();
        chat.dispose();
      });

      // Set up the exact bug this tab exists to fix: a dependent feature
      // (Afterglow) switched ON while its requirement (the Realism
      // Engine) is still OFF — the default state — so the unmet-dependency
      // chip/warning have something real to report from the first frame.
      await storage.realismSettings.setNsfwCooldownDefault(true);
      expect(
        storage.realismSettings.realismDefault,
        isFalse,
        reason:
            'this whole net is meaningless unless the engine starts '
            'OFF, which is the production default',
      );

      final scrollable = find.byType(Scrollable).first;
      Finder rowFor(String label) =>
          find.ancestor(of: find.text(label), matching: find.byType(Row)).first;
      Future<void> scrollTo(Finder finder) =>
          tester.scrollUntilVisible(finder, 300, scrollable: scrollable);
      Future<void> tapRow(String label) async {
        final labelFinder = find.text(label);
        await scrollTo(labelFinder);
        final sw = find.descendant(
          of: rowFor(label),
          matching: find.byType(Switch),
        );
        await tester.ensureVisible(sw);
        await tester.pump();
        await tester.tap(sw, warnIfMissed: true);
        await tester.pump(const Duration(milliseconds: 250));
        await tester.pump(const Duration(milliseconds: 250));
      }

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
      await tester.pump(const Duration(milliseconds: 300));

      // Pin 1: every feature row is a reachable landmark. This tab is the
      // single home for these switches — a missing label means a row
      // silently failed to render.
      const allRowLabels = [
        'Realism Engine',
        'Afterglow',
        'Needs',
        'Passage of Time',
        'Story Weather',
        'Temperatures in °F',
        'The Journal',
        'Dreams',
        'Promises',
        'Ambitions',
        'Welcome-back recap',
        'Character notices your absence',
      ];
      for (final label in allRowLabels) {
        final finder = find.text(label);
        await scrollTo(finder);
        expect(finder, findsOneWidget, reason: '"$label" row is missing');
      }

      // Pin 2: THE BUG THIS TAB FIXES. With the Realism Engine off, the rows
      // that work without it must stay visible AND keep a live Switch —
      // previously they were nested inside a realism-only block and the
      // whole block, switch included, vanished when the engine was off.
      const engineIndependentLabels = [
        'Welcome-back recap',
        'Story Weather',
        'The Journal',
        'Ambitions',
        'Passage of Time',
      ];
      for (final label in engineIndependentLabels) {
        final finder = find.text(label);
        await scrollTo(finder);
        expect(
          finder,
          findsOneWidget,
          reason:
              '"$label" must stay visible with the Realism Engine '
              'off — that is precisely what this tab exists to guarantee',
        );
        expect(
          find.descendant(of: rowFor(label), matching: find.byType(Switch)),
          findsOneWidget,
          reason:
              '"$label" switch must stay reachable with the Realism '
              'Engine off, not just its label text',
        );
      }

      // Pin 4: an unmet requirement GATES the row — the chip states the
      // requirement AND the switch goes dead. This is the maintainer's
      // 2026-08-07 correction: the first draft left dependants live and
      // stacked warning banners instead, which read as a wall of nags.
      // Needs, Afterglow and Passage of Time share the same requirement, so
      // the chip assertion is findsWidgets by design.
      final afterglowLabel = find.text('Afterglow');
      await scrollTo(afterglowLabel);
      expect(
        find.textContaining('needs the Realism Engine'),
        findsWidgets,
        reason: 'the dependency chip must report what a row requires',
      );
      final gatedSwitch = tester.widget<Switch>(
        find
            .descendant(of: rowFor('Afterglow'), matching: find.byType(Switch))
            .first,
      );
      expect(
        gatedSwitch.onChanged,
        isNull,
        reason:
            'with the Realism Engine off, a row that requires it must '
            'be GATED — a dead switch, not a live one with a warning',
      );

      // …and a row with no unmet requirement stays live in the same frame,
      // so the pin cannot pass by disabling everything.
      final journalLabel = find.text('The Journal');
      await scrollTo(journalLabel);
      final liveSwitch = tester.widget<Switch>(
        find
            .descendant(
              of: rowFor('The Journal'),
              matching: find.byType(Switch),
            )
            .first,
      );
      expect(
        liveSwitch.onChanged,
        isNotNull,
        reason:
            'an independent row must stay tappable while dependants '
            'are gated',
      );

      // Pin 5a: the away-threshold dropdown stays hidden until its own
      // switch (absence acknowledgement) is on.
      expect(
        find.text('Away for at least'),
        findsNothing,
        reason:
            'threshold dropdown must not render before absence '
            'acknowledgement is switched on',
      );

      // Pin 3: real taps on three different rows, across three different
      // groups, flip the real storage flags — including "Story Weather",
      // one of the rows named above as previously hidden by the engine-off
      // bug, tapped here while the engine is STILL off.
      expect(storage.realismSettings.absenceBannerEnabled, isTrue);
      await tapRow('Welcome-back recap');
      expect(
        storage.realismSettings.absenceBannerEnabled,
        isFalse,
        reason:
            'tapping the recap switch must flip '
            'storage.realismSettings.absenceBannerEnabled',
      );

      expect(storage.realismSettings.realismDefault, isFalse);
      expect(storage.realismSettings.weatherEnabled, isTrue);
      await tapRow('Story Weather');
      expect(
        storage.realismSettings.weatherEnabled,
        isFalse,
        reason:
            'tapping Story Weather must flip storage.realismSettings.weatherEnabled '
            'even though the Realism Engine is off — the entire point of '
            'this tab',
      );

      expect(storage.realismSettings.realismDefault, isFalse);
      expect(storage.memorySettings.journalEnabled, isTrue);
      await tapRow('The Journal');
      expect(
        storage.memorySettings.journalEnabled,
        isFalse,
        reason:
            'tapping The Journal must flip storage.memorySettings.journalEnabled '
            'even though the Realism Engine is off — another row this tab '
            'exists to rescue',
      );

      // Pin 5b: turning the absence-acknowledgement switch on reveals the
      // threshold dropdown.
      await tapRow('Character notices your absence');
      expect(storage.realismSettings.absenceAckEnabled, isTrue);
      final thresholdFinder = find.text('Away for at least');
      await scrollTo(thresholdFinder);
      expect(
        thresholdFinder,
        findsOneWidget,
        reason:
            'the away-threshold dropdown must appear once absence '
            'acknowledgement is switched on',
      );
    },
  );
}
