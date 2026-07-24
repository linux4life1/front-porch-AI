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

// The point of the @riverpod codegen standard: every provider is testable in
// a bare ProviderContainer — no widgets, no pumping, no app bootstrap.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/chat/milestone_feed.dart';
import 'package:front_porch_ai/services/chat/milestone_providers.dart';
import 'package:front_porch_ai/services/chat/weather_providers.dart';
import 'package:front_porch_ai/ui/chat_components/overlays/absence_recap_banner.dart';

void main() {
  test('dailyWeather: per-argument memoization, deterministic values', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final date = DateTime(2026, 1, 15);
    final a = container.read(
      dailyWeatherProvider(sessionSeed: 's', dayCount: 3, date: date),
    );
    final b = container.read(
      dailyWeatherProvider(sessionSeed: 's', dayCount: 3, date: date),
    );
    final c = container.read(
      dailyWeatherProvider(sessionSeed: 's', dayCount: 4, date: date),
    );
    expect(a, same(b), reason: 'same args → memoized instance');
    expect(a == c, isFalse, reason: 'different day → new weather');
  });

  test('MilestoneTimeline AsyncNotifier resolves in a bare container',
      () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    // A db-less feed resolves to const [] — proves the async build wires
    // through AsyncValue with zero app bootstrap.
    final entries = await container.read(
      milestoneTimelineProvider(
        feed: MilestoneFeed(getDb: () => null),
        sessionId: 's',
        characterId: 'c',
        revision: 0,
        messages: const [],
      ).future,
    );
    expect(entries, isEmpty);
  });

  test('DismissedAbsenceBanners: dismiss survives (keepAlive) per session',
      () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(dismissedAbsenceBannersProvider), isEmpty);
    container
        .read(dismissedAbsenceBannersProvider.notifier)
        .dismiss('session-1');
    expect(
      container.read(dismissedAbsenceBannersProvider),
      contains('session-1'),
    );
    expect(
      container.read(dismissedAbsenceBannersProvider),
      isNot(contains('session-2')),
    );
  });
}
