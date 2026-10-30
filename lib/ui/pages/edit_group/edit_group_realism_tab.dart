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

import 'package:front_porch_ai/ui/widgets/group_realism_dynamics_editor.dart';

/// Realism & Dynamics tab of the group editor. A spinner until the roster
/// is in (the editor seeds from the whole member list once). Edits flow
/// straight into the two blobs the page's Save persists; the editor owns
/// its own display state, so a new [key] is what makes it re-read them.
class EditGroupRealismTab extends StatelessWidget {
  const EditGroupRealismTab({
    super.key,
    required this.loaded,
    required this.members,
    required this.defaultMemberJson,
    required this.baselineJson,
    required this.onChanged,
  });

  final bool loaded;
  final List<GroupRealismMember> members;
  final String defaultMemberJson;
  final String baselineJson;
  final void Function(String defaultMemberJson, String baselineJson) onChanged;

  @override
  Widget build(BuildContext context) {
    if (!loaded) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: CircularProgressIndicator(),
        ),
      );
    }
    return GroupRealismDynamicsEditor(
      members: members,
      initialDefaultMemberJson: defaultMemberJson,
      initialBaselineJson: baselineJson,
      onChanged: onChanged,
    );
  }
}
