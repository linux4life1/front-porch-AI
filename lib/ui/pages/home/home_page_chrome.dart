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

part of '../home_page.dart';

/// Mode toggle and the model-load status bar.
/// Open-chat / menus / folder handlers live in home_page_chrome.actions.dart.
/// Home-tap source scans read that actions part, not this file.
extension _HomePageChrome on _HomePageState {
  Widget _buildModeToggle() {
    return HomeModeToggle(
      showStories: _homeMode == HomeMode.stories,
      showWaifu: _homeMode == HomeMode.waifu,
      studio: _homeMode == HomeMode.stories,
      onShowChats: () => _setHomeMode(HomeMode.chats),
      onShowStories: () => _setHomeMode(HomeMode.stories),
      onShowWaifu: () => _setHomeMode(HomeMode.waifu),
    );
  }

  void _setHomeMode(HomeMode mode) {
    applyState(() => _homeMode = mode);
    Provider.of<AppState>(
      context,
      listen: false,
    ).setSidebarHidden(mode != HomeMode.chats);
  }

  /// Toggle row that shrinks instead of overflowing when the window is
  /// squeezed. Used on the empty-library and Stories chrome.
  Widget _modeToggleBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
      child: Row(
        children: [
          Flexible(
            child: Align(
              alignment: Alignment.centerLeft,
              child: _buildModeToggle(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _wrapWithStatusBar(BuildContext context, Widget content) {
    String status = '';
    var phase = KoboldPhase.stopped;
    try {
      final kobold = Provider.of<KoboldService>(context, listen: false);
      status = kobold.modelLoadingStatus;
      phase = kobold.phase;
    } catch (_) {}

    if (status.isEmpty) return content;

    return Column(
      children: [
        Expanded(child: content),
        KoboldStatusBar(status: status, phase: phase),
      ],
    );
  }
}
