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
import 'package:front_porch_ai/providers/app_state.dart';
import 'package:front_porch_ai/services/update_service.dart';
import 'package:front_porch_ai/ui/dialogs/update_dialog.dart';
import 'package:front_porch_ai/ui/pages/character_creator_page.dart';

class Sidebar extends StatelessWidget {
  const Sidebar({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final theme = Theme.of(context);

    return Container(
      width: 250,
      color: const Color(0xFF0F172A), // Dark slate
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
          _SidebarItem(
            icon: Icons.home_outlined,
            label: 'Home',
            isSelected: appState.selectedIndex == 0,
            onTap: () => appState.setIndex(0),
          ),
          InkWell(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => CharacterCreatorPage(),
              ),
            ),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 12.0),
              margin: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
              child: Row(
                children: [
                  const Icon(
                    Icons.psychology,
                    color: Colors.amberAccent,
                    size: 22,
                  ),
                  const SizedBox(width: 12),
                  const Flexible(
                    child: Text(
                      'AI Character Creator',
                      style: TextStyle(
                        color: Colors.amberAccent,
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
          _SidebarItem(
            icon: Icons.cloud_sync_outlined,
            label: 'Cloud Sync',
            isSelected: appState.selectedIndex == 6,
            onTap: () => appState.setIndex(6),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
            child: InkWell(
              onTap: () => launchUrl(Uri.parse('https://ko-fi.com/sosukeaizen37411')),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 12.0),
                child: const Row(
                  children: [
                    Icon(
                      Icons.coffee_outlined,
                      color: Color(0xFFFF5E5B), // Ko-fi brand coral
                      size: 22,
                    ),
                    SizedBox(width: 12),
                    Flexible(
                      child: Text(
                        'Buy Me a Coffee ☕',
                        style: TextStyle(color: Colors.white70),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Tooltip(
                  message: 'Join our Discord Server',
                  child: GestureDetector(
                    onTap: () => launchUrl(Uri.parse('https://discord.gg/e4tET6rpdv')),
                    child: const MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: Icon(Icons.discord, size: 20, color: Colors.white54),
                    ),
                  ),
                ),
                Tooltip(
                  message: 'Join our Matrix Server',
                  child: GestureDetector(
                    onTap: () => launchUrl(Uri.parse('https://matrix.dreamersai.art')),
                    child: const MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: Icon(Icons.grid_view_rounded, size: 20, color: Colors.white54),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Consumer<UpdateService>(
              builder: (context, updateService, _) {
                final version = updateService.currentVersion.isNotEmpty
                    ? 'v${updateService.currentVersion}'
                    : 'v0.0.0';
                return Row(
                  children: [
                    Text(
                      version,
                      style: theme.textTheme.bodySmall?.copyWith(color: Colors.white38),
                    ),
                    if (updateService.updateAvailable) ...[
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () => UpdateDialog.show(context),
                        child: const Tooltip(
                          message: 'Update available!',
                          child: Icon(Icons.arrow_circle_up, size: 18, color: Colors.greenAccent),
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
            color: isSelected ? Colors.white.withValues(alpha: 0.1) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 12.0),
          child: Row(
            children: [
              Icon(
                icon,
                color: isSelected ? Colors.white : Colors.white70,
                size: 22,
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.white70,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
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
