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

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/pages/home/library_selection.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

/// The selection counted the way the grid counts it: picks that still
/// exist, and how many of them the current search or folder hides.
SelectionTally tallyHomeSelection(
  BuildContext context,
  LibrarySelection selection, {
  required String? activeFolderId,
  required String query,
  required SearchScope scope,
  required String sortMode,
}) {
  final repo = Provider.of<CharacterRepository>(context, listen: false);
  final groupRepo = Provider.of<GroupChatRepository>(context, listen: false);
  final view = libraryViewOf(
    characters: repo.characters,
    groups: groupRepo.groups,
    folders: Provider.of<FolderService>(context, listen: false),
    activeFolderId: activeFolderId,
    query: query,
    scope: scope,
    sortMode: sortMode,
  );
  return tallySelection(
    view,
    characterIds: selection.characterIds,
    groupIds: selection.groupIds,
    library: repo.characters,
    groupLibrary: groupRepo.groups,
  );
}
