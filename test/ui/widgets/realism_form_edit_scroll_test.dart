// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// OPEN_SECTION=edit must scroll the Relationship header *block* (the 20px
// gap plus the header) below the Details TabBar, so the gap is not clipped
// under the sticky tab ink.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/ui/pages/home/open_section_env.dart';
import 'package:front_porch_ai/ui/widgets/realism_form_section.dart';

Widget _harness() => MaterialApp(
  home: DefaultTabController(
    length: 1,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Edit Character'),
        bottom: const TabBar(
          tabs: [
            Tab(icon: Icon(Icons.person_outline, size: 18), text: 'Details'),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Push Relationship below the fold at ~1280x720 dialog height
            // so ensureVisible actually scrolls.
            const SizedBox(height: 400, width: double.infinity),
            RealismFormSection(
              enabled: true,
              onEnabledChanged: (_) {},
              timeOfDay: 'morning',
              onTimeOfDayChanged: (_) {},
              dayCount: 1,
              onDayCountChanged: (_) {},
              shortTermBond: 0,
              onShortTermBondChanged: (_) {},
              longTermBond: 0,
              onLongTermBondChanged: (_) {},
              trustLevel: 0,
              onTrustLevelChanged: (_) {},
              emotion: '',
              onEmotionChanged: (_) {},
              emotionIntensity: 'mild',
              onEmotionIntensityChanged: (_) {},
              nsfwCooldownEnabled: false,
              onNsfwCooldownChanged: (_) {},
              chaosModeEnabled: false,
              onChaosModeChanged: (_) {},
              ambitions: const [],
              onAmbitionsChanged: (_) {},
              likes: const [],
              onLikesChanged: (_) {},
              dislikes: const [],
              onDislikesChanged: (_) {},
              worn: const [],
              onWornChanged: (_) {},
              carrying: const [],
              onCarryingChanged: (_) {},
              realismVerificationEnabled: false,
              onRealismVerificationChanged: (_) {},
            ),
          ],
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('edit scroll parks Relationship gap below the Details tab', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(780, 624));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();

    OpenSectionEnv.ensureRelationshipHeaderVisible(
      tester.element(find.byType(Scaffold)),
    );
    await tester.pump();

    final relationshipTop = tester.getRect(find.text('Relationship')).top;
    final detailsBottom = tester.getRect(find.text('Details')).bottom;
    final tabBarBottom = tester.getRect(find.byType(TabBar)).bottom;
    expect(relationshipTop, greaterThan(detailsBottom));
    expect(relationshipTop, greaterThan(tabBarBottom));

    final cardBottom = tester
        .getRect(find.byKey(const Key('relationship-card')))
        .bottom;
    final emotionTop = tester.getRect(find.text('Starting Emotion')).top;
    expect(emotionTop - cardBottom, RealismFormSection.sectionHeaderGap);
  });
}
