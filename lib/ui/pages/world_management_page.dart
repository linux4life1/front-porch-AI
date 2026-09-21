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

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/dialogs/dialogs.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/character_creator/world_from_wiki/world_from_wiki_page.dart';
import 'package:front_porch_ai/ui/pages/worlds/worlds.dart';
import 'package:front_porch_ai/ui/dialogs/avatar_gallery/avatar_gallery_io.dart';
import 'package:front_porch_ai/utils/world_cover.dart';

// The hero header/stats, the Create/Edit World dialog frame, and its
// three content sections (Basic Information, Climate picker, Lorebook)
// live in these `part of` files (extensions on _WorldManagementPageState)
// to keep every file under the 500-LOC cap -- same pattern
// chat_service.dart and settings_page.dart use. They share this
// library's imports and access the page's private state directly, so
// behavior is unchanged.
part 'world_management_page.header.dart';
part 'world_management_page.dialog.dart';
part 'world_management_page.basics.dart';
part 'world_management_page.climate.dart';
part 'world_management_page.lorebook.dart';

class WorldManagementPage extends StatefulWidget {
  const WorldManagementPage({super.key});

  @override
  State<WorldManagementPage> createState() => _WorldManagementPageState();
}

class _WorldManagementPageState extends State<WorldManagementPage>
    with SingleTickerProviderStateMixin {
  late AnimationController _headerAnimController;
  late Animation<double> _headerGlowAnimation;

  @override
  void initState() {
    super.initState();
    _headerAnimController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);
    _headerGlowAnimation = Tween<double>(begin: 0.3, end: 0.7).animate(
      CurvedAnimation(parent: _headerAnimController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _headerAnimController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<WorldRepository>(
      builder: (context, repo, child) {
        return Scaffold(
          backgroundColor: AppColors.backgroundOf(context),
          body: CustomScrollView(
            slivers: [
              // Hero header
              SliverToBoxAdapter(child: _buildHeroHeader(context, repo)),

              // Stats section
              SliverToBoxAdapter(child: _buildStatsSection(context, repo)),

              // Section label
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(28, 24, 28, 12),
                  child: Row(
                    children: [
                      Container(
                        width: 3,
                        height: 18,
                        decoration: BoxDecoration(
                          color: AppColors.formMasterAccent,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Places (${repo.placeWorlds.length})',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary(context),
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // World grid
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 380,
                    childAspectRatio: 1.2,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                  ),
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final w = repo.placeWorlds[index];
                    return WorldPlaceCard(
                      world: w,
                      onEdit: () => _showWorldDialog(context, repo, w),
                      onExport: () => exportFpWorldFlow(context, repo, w),
                      onDelete: () => _confirmDelete(context, repo, w),
                    );
                  }, childCount: repo.placeWorlds.length),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _confirmDelete(BuildContext context, WorldRepository repo, World world) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete World?'),
        content: Text('Are you sure you want to delete "${world.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () {
              repo.deleteWorld(world);
              Navigator.pop(context);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
