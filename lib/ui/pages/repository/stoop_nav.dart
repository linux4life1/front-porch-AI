// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Stoop creator navigation. Detail and creator pages import this
// instead of each other.

import 'package:flutter/material.dart';

import 'package:front_porch_ai/ui/pages/repository/stoop_creator_page.dart';

/// Push a creator profile. [popFirst] closes the slide-in detail panel
/// so the profile is not stacked under the glass sheet.
void openStoopCreator(
  BuildContext context,
  String creatorId, {
  bool popFirst = false,
}) {
  if (popFirst) Navigator.of(context).pop();
  Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => StoopCreatorPage(creatorId: creatorId)),
  );
}
