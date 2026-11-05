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

// The web Settings POST's sidebar-order branches, split out of
// [SettingsWriter] because that file sits near the size limit. Mirrors the
// desktop's Reset pill and grip drags: each list is the visible ids in the
// new sequence, and the setter merges hidden ids back into their stored slots.

import 'package:front_porch_ai/services/services.dart';

/// Applies the sidebar-order keys of a web Settings POST body: the desktop
/// top-level order, the two accordion leaf orders, the web insight order, the
/// web Chat Tools order, and the Reset-to-default flag. Additive — an older
/// PWA ignores every key.
Future<void> applySidebarOrderWrite(
  StorageService storage,
  Map<String, dynamic> body,
) async {
  final ui = storage.uiSettings;

  final order = body['sidebarOrder'];
  if (order is List) {
    await ui.setSidebarOrder([
      for (final id in order)
        if (id is String && id.isNotEmpty) id,
    ]);
  }

  final leaf = body['sidebarLeafOrder'];
  if (leaf is Map) {
    for (final container in const ['story_tools', 'journal_memory']) {
      final list = leaf[container];
      if (list is List) {
        await ui.setSidebarLeafOrder(
          container,
          [for (final id in list) if (id is String && id.isNotEmpty) id],
        );
      }
    }
  }

  final webOrder = body['webSidebarOrder'];
  if (webOrder is List) {
    await ui.setWebSidebarOrder([
      for (final id in webOrder)
        if (id is String && id.isNotEmpty) id,
    ]);
  }

  final webTools = body['webSidebarToolsOrder'];
  if (webTools is List) {
    await ui.setWebSidebarToolsOrder([
      for (final id in webTools)
        if (id is String && id.isNotEmpty) id,
    ]);
  }

  // Reset-to-default: clear every stored key and restore the shipped order.
  if (body['resetSidebarLayout'] == true) {
    await ui.resetSidebarLayout();
  }
}
