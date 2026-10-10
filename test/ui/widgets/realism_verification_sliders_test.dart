// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// "Max reprocess passes" and "Strictness" tune Realism Verification. With
// Verification off they used to stay live, so a user could drag settings
// for a pass that never runs. They are disabled while it is off and come
// back, with the values they had, when it is switched on. The 1:1 creator,
// the AI creator and the group wizard's per-member card all draw this form.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/ui/widgets/realism_form_section.dart';

/// A page-like host that owns the verification state the way the creators do.
class _Host extends StatefulWidget {
  const _Host();

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  bool verify = false;
  int passes = 3;
  int strictness = 4;

  @override
  Widget build(BuildContext context) => MaterialApp(
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
          realismVerificationEnabled: verify,
          onRealismVerificationChanged: (v) => setState(() => verify = v),
          realismVerificationMaxReprocesses: passes,
          onRealismVerificationMaxReprocessesChanged: (v) =>
              setState(() => passes = v),
          realismVerificationStrictness: strictness,
          onRealismVerificationStrictnessChanged: (v) =>
              setState(() => strictness = v),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('verification sliders wait while Verification is off', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 2600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const _Host());
    await tester.pumpAndSettle();
    final host = tester.state<_HostState>(find.byType(_Host));

    Slider slider(String labelStart) {
      final label = find.textContaining(labelStart);
      expect(label, findsOneWidget);
      // Each slider sits right under its label in the same column.
      final labelY = tester.getTopLeft(label).dy;
      final sliders = find.byType(Slider).evaluate().toList()
        ..sort(
          (a, b) => tester
              .getTopLeft(find.byWidget(a.widget))
              .dy
              .compareTo(tester.getTopLeft(find.byWidget(b.widget)).dy),
        );
      final below = sliders.firstWhere(
        (e) => tester.getTopLeft(find.byWidget(e.widget)).dy > labelY,
      );
      return below.widget as Slider;
    }

    final passes = slider('Max reprocess passes');
    final strict = slider('Strictness');
    expect(passes.onChanged, isNull, reason: 'off: passes slider disabled');
    expect(strict.onChanged, isNull, reason: 'off: strictness slider disabled');

    // A drag on a disabled slider changes nothing.
    await tester.drag(find.byWidget(passes), const Offset(-300, 0));
    await tester.pumpAndSettle();
    expect(host.passes, 3);

    // Switch Verification on: both come back live with their values.
    final toggle = find.ancestor(
      of: find.text('Realism Verification (Director/Verifier)'),
      matching: find.byWidgetPredicate((w) => w is Row),
    );
    await tester.tap(
      find.descendant(of: toggle.first, matching: find.byType(Switch)),
    );
    await tester.pumpAndSettle();
    expect(host.verify, isTrue);

    final passesOn = slider('Max reprocess passes');
    final strictOn = slider('Strictness');
    expect(passesOn.onChanged, isNotNull);
    expect(strictOn.onChanged, isNotNull);
    expect(passesOn.value, 3);
    expect(strictOn.value, 4);
  });
}
