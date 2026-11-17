// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';

import 'package:front_porch_ai/ui/widgets/realism_form_section/realism_form_section.dart';

/// A group member's Starts Away pick: how every chat the group CREATES
/// starts them (docs/design/group-initial-presence.md). Member-only — a
/// 1:1 card has no hold to author, and the wizard's Members step picks
/// it there too. Not an 18+ feature, and not a Realism Engine feature
/// (ruling R6): it rides in the Optional Features card, above Chaos,
/// with the engine on or off. [memberName] names the member as the
/// editor has it now, like the web row's hint does.
Widget memberStartsAwayRow(
  BuildContext context,
  bool value,
  ValueChanged<bool> onChanged, {
  String? memberName,
}) => buildRealismToggleRow(
  icon: Icons.pause_circle_outline,
  label: 'Starts away',
  subtitle:
      'Every chat you make with this group starts '
      "${memberName ?? 'them'} Away, before any turn runs. Only Back at "
      'the door brings them in - a chat you reopen keeps its own.',
  value: value,
  onChanged: onChanged,
  context: context,
);
