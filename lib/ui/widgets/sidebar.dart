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
import 'package:url_launcher/url_launcher.dart';
import 'package:provider/provider.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/providers/app_state.dart';
import 'package:front_porch_ai/services/update_service.dart';
import 'package:front_porch_ai/ui/dialogs/update_dialog.dart';
import 'package:front_porch_ai/ui/pages/character_creator_page.dart';
import 'package:front_porch_ai/ui/pages/create_group_chat_page.dart';
import 'package:front_porch_ai/ui/pages/repository_page.dart';
import 'package:front_porch_ai/ui/pages/backups_page.dart';

class Sidebar extends StatelessWidget {
  const Sidebar({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final theme = Theme.of(context);

    return Container(
      width: 250,
      color: AppColors.backgroundOf(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                'FRONT PORCH AI',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
            ),
          ),
          // Nav list scrolls when the window is short, so the footer stays
          // pinned and the column never overflows (the brand stays above it).
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SidebarItem(
                    icon: Icons.home_outlined,
                    label: 'Home',
                    isSelected: appState.selectedIndex == 0,
                    onTap: () => appState.setIndex(0),
                  ),
                  // The Stoop (community character hub) — a flagship destination, so it
                  // sits right under Home.
                  InkWell(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const RepositoryPage()),
                    ),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.resolve(
                          context,
                          Colors.tealAccent.withValues(alpha: 0.08),
                          Colors.teal.withValues(alpha: 0.10),
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(
                        vertical: 12.0,
                        horizontal: 12.0,
                      ),
                      margin: const EdgeInsets.symmetric(
                        horizontal: 12.0,
                        vertical: 4.0,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.travel_explore,
                            color: AppColors.resolve(
                              context,
                              Colors.tealAccent,
                              Colors.teal.shade700,
                            ),
                            size: 22,
                          ),
                          const SizedBox(width: 12),
                          Flexible(
                            child: Text(
                              'The Stoop',
                              style: TextStyle(
                                color: AppColors.resolve(
                                  context,
                                  Colors.tealAccent,
                                  Colors.teal.shade700,
                                ),
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => CharacterCreatorPage()),
                    ),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(
                        vertical: 12.0,
                        horizontal: 12.0,
                      ),
                      margin: const EdgeInsets.symmetric(
                        horizontal: 12.0,
                        vertical: 4.0,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.psychology,
                            color: AppColors.resolve(
                              context,
                              Colors.amberAccent,
                              Colors.amber.shade700,
                            ),
                            size: 22,
                          ),
                          const SizedBox(width: 12),
                          Flexible(
                            child: Text(
                              'AI Character Creator',
                              style: TextStyle(
                                color: AppColors.resolve(
                                  context,
                                  Colors.amberAccent,
                                  Colors.amber.shade700,
                                ),
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  _SidebarItem(
                    icon: Icons.add_circle_outline,
                    label: 'Create Character',
                    isSelected: appState.selectedIndex == 1,
                    onTap: () => appState.setIndex(1),
                  ),
                  InkWell(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const CreateGroupChatPage(),
                      ),
                    ),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF7C3AED).withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(
                        vertical: 12.0,
                        horizontal: 12.0,
                      ),
                      margin: const EdgeInsets.symmetric(
                        horizontal: 12.0,
                        vertical: 4.0,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.group_add,
                            color: const Color(0xFF7C3AED),
                            size: 22,
                          ),
                          const SizedBox(width: 12),
                          Flexible(
                            child: Text(
                              'Create Group Chat',
                              style: TextStyle(
                                color: const Color(0xFF7C3AED),
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  _SidebarItem(
                    icon: Icons.dns_outlined,
                    label: 'Manage Models',
                    isSelected: appState.selectedIndex == 2,
                    onTap: () => appState.setIndex(2),
                  ),
                  _SidebarItem(
                    icon: Icons.settings_outlined,
                    label: 'Settings',
                    isSelected: appState.selectedIndex == 3,
                    onTap: () => appState.setIndex(3),
                  ),
                  _SidebarItem(
                    icon: Icons.person_outline,
                    label: 'User Persona',
                    isSelected: appState.selectedIndex == 4,
                    onTap: () => appState.setIndex(4),
                  ),
                  _SidebarItem(
                    icon: Icons.public_outlined,
                    label: 'Worlds',
                    isSelected: appState.selectedIndex == 5,
                    onTap: () => appState.setIndex(5),
                  ),
                  // Local DB Backups & Restore — preserved from the removed Cloud Sync
                  // page (it was never cloud-dependent). Opens as its own full page.
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12.0,
                      vertical: 4.0,
                    ),
                    child: InkWell(
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const BackupsPage()),
                      ),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          vertical: 12.0,
                          horizontal: 12.0,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.settings_backup_restore,
                              color: AppColors.iconSecondary(context),
                              size: 22,
                            ),
                            const SizedBox(width: 12),
                            Flexible(
                              child: Text(
                                'Backups & Restore',
                                style: TextStyle(
                                  color: AppColors.textSecondary(context),
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12.0,
                      vertical: 4.0,
                    ),
                    child: InkWell(
                      onTap: () =>
                          launchUrl(Uri.parse('https://discord.gg/e4tET6rpdv')),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          vertical: 12.0,
                          horizontal: 12.0,
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.discord,
                              color: Color(0xFF5865F2), // Discord brand blurple
                              size: 22,
                            ),
                            const SizedBox(width: 12),
                            Flexible(
                              child: Text(
                                'Join the Discord',
                                style: TextStyle(
                                  color: AppColors.textSecondary(context),
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12.0,
                      vertical: 4.0,
                    ),
                    child: InkWell(
                      onTap: () => launchUrl(
                        Uri.parse('https://ko-fi.com/sosukeaizen37411'),
                      ),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          vertical: 12.0,
                          horizontal: 12.0,
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.coffee_outlined,
                              color: Color(0xFFFF5E5B), // Ko-fi brand coral
                              size: 22,
                            ),
                            const SizedBox(width: 12),
                            Flexible(
                              child: Text(
                                'Buy Me a Coffee ☕',
                                style: TextStyle(
                                  color: AppColors.textSecondary(context),
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 8.0,
            ),
            child: Consumer<UpdateService>(
              builder: (context, updateService, _) {
                final version = updateService.currentVersion.isNotEmpty
                    ? updateService.displayCurrentVersion
                    : 'v0.0.0';
                return Row(
                  children: [
                    Text(
                      version,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.textTertiary(context),
                      ),
                    ),
                    if (updateService.updateAvailable) ...[
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () => UpdateDialog.show(context),
                        child: const Tooltip(
                          message: 'Update available!',
                          child: Icon(
                            Icons.arrow_circle_up,
                            size: 18,
                            color: Colors.greenAccent,
                          ),
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          decoration: BoxDecoration(
            // Subtle selection: light blue tint in light mode (paper bg), low-alpha white in dark.
            // Reuses AppColors.resolve (existing scaffold) — no new helper or private method.
            color: isSelected
                ? AppColors.resolve(
                    context,
                    Colors.white.withValues(alpha: 0.08),
                    const Color(0xFFBFDBFE),
                  )
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 12.0),
          child: Row(
            children: [
              Icon(
                icon,
                color: isSelected
                    ? AppColors.textPrimary(context)
                    : AppColors.textSecondary(context),
                size: 22,
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    color: isSelected
                        ? AppColors.textPrimary(context)
                        : AppColors.textSecondary(context),
                    fontWeight: isSelected
                        ? FontWeight.w600
                        : FontWeight.normal,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
