// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/dialogs/group_settings/group_settings.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

/// Main settings dialog for a Group Chat.
/// This is the central place for all per-group and per-character configuration.
class GroupSettingsDialog extends StatefulWidget {
  final ChatService chatService;
  final GroupChatRepository? groupRepo;

  const GroupSettingsDialog({
    super.key,
    required this.chatService,
    this.groupRepo,
  });

  @override
  State<GroupSettingsDialog> createState() => _GroupSettingsDialogState();
}

class _GroupSettingsDialogState extends State<GroupSettingsDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _generalTabKey = GlobalKey<GroupGeneralTabState>();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// Flushes the General tab's controllers onto the live group and persists.
  ///
  /// Shared by Save, Done, and the X/Close paths. Every other tab edits the
  /// live [GroupChat] as the user types, so closing keeps those edits; General
  /// holds name / scenario / first message / turn rules in controllers until
  /// this runs — which is why the header X and footer Close used to throw
  /// away everything typed there with no warning.
  /// Returns true when the group was actually written to the repository.
  bool _commitEdits() {
    _generalTabKey.currentState?.applyToLiveGroup();
    final g = widget.chatService.activeGroup;
    if (g == null || widget.groupRepo == null) return false;
    widget.groupRepo!.save(g);
    return true;
  }

  /// Header X / footer Close: if General is dirty, warn; Save applies then
  /// pops, Discard pops without applying, Keep editing stays. Clean close
  /// pops immediately. Done always commits (it is the primary apply+leave).
  Future<void> _requestClose() async {
    final dirty = _generalTabKey.currentState?.hasUnsavedChanges ?? false;
    if (dirty) {
      final choice = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.surfaceOf(ctx),
          title: Text(
            'Unsaved General changes',
            style: TextStyle(color: AppColors.textPrimary(ctx)),
          ),
          content: Text(
            'Name, scenario, opening message, or turn rules have not been applied yet.',
            style: TextStyle(color: AppColors.textSecondary(ctx)),
          ),
          actions: [
            warmDialogCancel(ctx, label: 'Keep editing'),
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(
                'Discard',
                style: TextStyle(color: AppColors.bondNegOf(ctx)),
              ),
            ),
            warmDialogConfirm(
              ctx,
              label: 'Save',
              onPressed: () => Navigator.pop(ctx, true),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (choice == null) return;
      if (choice) _commitEdits();
    }
    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: 720,
        height: 620,
        decoration: BoxDecoration(
          color: AppColors.surfaceOf(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.borderOf(context)),
        ),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerOf(context),
                borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
              ),
              child: Row(
                children: [
                  Text(
                    'Group Settings',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary(context),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: Icon(
                      Icons.close,
                      color: AppColors.iconSecondary(context),
                    ),
                    onPressed: _requestClose,
                  ),
                ],
              ),
            ),

            // Tabs
            TabBar(
              controller: _tabController,
              isScrollable: true,
              tabs: const [
                Tab(text: 'Prompt Engineering'),
                Tab(text: 'Memory & RAG'),
                Tab(text: 'Realism'),
                Tab(text: 'Needs'),
                Tab(text: 'General'),
                Tab(text: 'Lorebook & Worlds'),
              ],
            ),

            Divider(height: 1, color: AppColors.borderOf(context)),

            // Tab Content
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  GroupPromptEngineeringTab(
                    chatService: widget.chatService,
                    groupRepo: widget.groupRepo,
                  ),
                  GroupMemoryRAGTab(
                    chatService: widget.chatService,
                    groupRepo: widget.groupRepo,
                  ),
                  GroupRealismNeedsTab(
                    chatService: widget.chatService,
                    groupRepo: widget.groupRepo,
                  ),
                  GroupNeedsTab(
                    chatService: widget.chatService,
                    groupRepo: widget.groupRepo,
                  ),
                  GroupGeneralTab(
                    key: _generalTabKey,
                    chatService: widget.chatService,
                    groupRepo: widget.groupRepo,
                  ),
                  GroupLorebookWorldsTab(
                    chatService: widget.chatService,
                    groupRepo: widget.groupRepo,
                  ),
                ],
              ),
            ),

            // Footer
            //
            // Philosophy for this dialog:
            // - Most controls edit the live GroupChat in memory (immediate effect on the running session).
            // - There is only ONE persistence action: "Save" writes the current state to the repository.
            // - Per-tab save buttons were removed as part of the 2026 UX overhaul (they were confusing and redundant).
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerOf(context),
                borderRadius: BorderRadius.vertical(
                  bottom: Radius.circular(12),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _requestClose,
                    child: Text(
                      'Close',
                      style: TextStyle(color: AppColors.textSecondary(context)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (widget.groupRepo != null)
                    OutlinedButton(
                      onPressed: () {
                        // General tab edits live in controllers until Save.
                        if (_commitEdits()) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Group settings saved.'),
                              backgroundColor: Color(0xFF10B981),
                            ),
                          );
                        }
                      },
                      child: Text(
                        'Save',
                        style: TextStyle(color: AppColors.textPrimary(context)),
                      ),
                    ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () {
                      // Done is the primary action: commit, then close. It used
                      // to pop straight out, silently losing the General tab.
                      _commitEdits();
                      Navigator.pop(context);
                    },
                    child: const Text('Done'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
