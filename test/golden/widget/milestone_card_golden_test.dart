// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The Boons & Bogies milestone card (docs/design/boons-and-bogies.md §7) —
// the new shared surface's golden, light and dark, from the approved mockup
// (docs/design/mockups/boons-and-bogies-milestones.html). The card alone,
// badge stamped: the celebration is the shared sim, pinned by its vectors.

@Tags(['golden'])
@TestOn('linux')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/chat_service.dart' show MilestoneView;
import 'package:front_porch_ai/ui/widgets/milestone/milestone.dart';

import '../support/golden_app.dart';

MilestoneView _view({
  required String kind,
  required String pill,
  required String title,
  required String tierLine,
  required String text,
  required String receipt,
  String ask = '',
  bool inGroup = false,
  double meter = 0.3,
}) => MilestoneView(
  id: 'm-golden',
  kind: kind,
  status: 'pending',
  seen: false,
  title: title,
  pill: pill,
  tierLine: tierLine,
  text: text,
  receipt: receipt,
  ask: ask,
  ownerName: 'Mira Vale',
  inGroup: inGroup,
  meter: meter,
);

Widget _card(MilestoneView view) => Center(
  child: SizedBox(
    width: 340,
    child: MilestoneCard(
      view: view,
      onAccept: () {},
      onReject: () {},
      onClose: () {},
    ),
  ),
);

void main() {
  testWidgets('milestone card — new boon', (tester) async {
    await expectThemedGoldens(
      tester,
      child: _card(
        _view(
          kind: 'new_boon',
          pill: 'BOON',
          title: 'New boon',
          tierLine: 'Novice · new',
          text: 'catches what falls before it lands',
          receipt: 'Seen in #14 and #18',
        ),
      ),
      group: 'milestone_card',
      name: 'new_boon',
      surface: const Size(380, 340),
    );
  });

  testWidgets('milestone card — Master bogey in a group', (tester) async {
    await expectThemedGoldens(
      tester,
      child: _card(
        _view(
          kind: 'master_bogey',
          pill: 'BOGEY',
          title: 'Master · bogey',
          tierLine: 'Skilled → Master · fired 12 times',
          text: 'bad temper when cornered',
          receipt: 'Seen in #93',
          ask: 'This has become part of who Mira Vale is. Make it permanent?',
          inGroup: true,
          meter: 0.9,
        ),
      ),
      group: 'milestone_card',
      name: 'master_bogey_group',
      surface: const Size(380, 400),
    );
  });

  testWidgets('milestone card — bogey overcome', (tester) async {
    await expectThemedGoldens(
      tester,
      child: _card(
        _view(
          kind: 'overcome',
          pill: 'BOGEY',
          title: 'Bogey overcome',
          tierLine: 'Skilled · pinned',
          text: 'bad temper when cornered',
          receipt: 'Coped in #58, #64 and #71',
          ask: 'Mira Vale has overcome this. Let it go?',
          meter: 0.45,
        ),
      ),
      group: 'milestone_card',
      name: 'overcome',
      surface: const Size(380, 380),
    );
  });
}
