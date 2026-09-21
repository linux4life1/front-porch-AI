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
      onShowChats: () => applyState(() => _homeMode = HomeMode.chats),
      onShowStories: () => applyState(() => _homeMode = HomeMode.stories),
      onShowWaifu: () => applyState(() => _homeMode = HomeMode.waifu),
    );
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
    try {
      final kobold = Provider.of<KoboldService>(context, listen: false);
      status = kobold.modelLoadingStatus;
    } catch (_) {}

    if (status.isEmpty) return content;

    return Column(
      children: [
        Expanded(child: content),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerOf(context),
            border: Border(top: BorderSide(color: AppColors.borderOf(context))),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                status,
                style: TextStyle(
                  color: AppColors.textSecondary(context),
                  fontSize: 13,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  minHeight: 4,
                  backgroundColor: AppColors.surfaceContainerOf(context),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    AppColors.porchHoneyOf(context),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
