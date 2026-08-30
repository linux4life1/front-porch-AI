// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Edit Details: Relationship must get the same 20px gap above its header as
// Starting Emotion, including when Needs is present.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/ui/widgets/realism_form_section.dart';

Widget _form({Widget? needs}) => MaterialApp(
  home: Scaffold(
    body: SingleChildScrollView(
      child: RealismFormSection(
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
        needsFormSection: needs,
      ),
    ),
  ),
);

void main() {
  testWidgets('Relationship header has 20px above it when Needs is present', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(520, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _form(
        needs: const SizedBox(
          key: Key('needs-stub'),
          height: 48,
          width: double.infinity,
          child: ColoredBox(color: Color(0x11000000)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final needsBottom = tester
        .getRect(find.byKey(const Key('needs-stub')))
        .bottom;
    final relationshipTop = tester.getRect(find.text('Relationship')).top;
    expect(relationshipTop - needsBottom, RealismFormSection.sectionHeaderGap);

    // Starting Emotion uses the same token above its header, measured from
    // the bordered Relationship card — not a looser greaterThan.
    final cardBottom = tester
        .getRect(find.byKey(const Key('relationship-card')))
        .bottom;
    final emotionTop = tester.getRect(find.text('Starting Emotion')).top;
    expect(emotionTop - cardBottom, RealismFormSection.sectionHeaderGap);
  });

  testWidgets('Relationship still has a 20px gap when Needs is absent', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(520, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_form());
    await tester.pumpAndSettle();

    expect(find.text('Relationship'), findsOneWidget);
    expect(find.text('Starting Emotion'), findsOneWidget);

    final cardBottom = tester
        .getRect(find.byKey(const Key('relationship-card')))
        .bottom;
    final emotionTop = tester.getRect(find.text('Starting Emotion')).top;
    expect(emotionTop - cardBottom, RealismFormSection.sectionHeaderGap);
  });
}
