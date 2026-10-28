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

import 'package:flutter/material.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/world_repository.dart';
import 'package:front_porch_ai/ui/pages/story_setup_page.dart';
import 'package:front_porch_ai/ui/story_studio/story_world_lookup.dart';

/// "Write a story here" on a world card or a place row
/// (docs/design/stories-in-worlds.md §3.4): New Story opens on its Idea
/// step with the world picked, starting at the world's starred place or at
/// the place itself. The discovery path for authors who build worlds first.
Future<void> writeStoryHere(
  BuildContext context,
  WorldRepository worlds,
  World world,
) async {
  final pick = storyWorldPickFor(world, worlds);
  if (pick == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('That world is no longer in the library.')),
    );
    return;
  }
  await Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => StorySetupPage(fromWorld: pick)));
}
