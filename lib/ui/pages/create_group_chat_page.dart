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
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/pages/chat_page.dart';
import 'package:front_porch_ai/ui/pages/create_group_chat_page/create_group_chat_page.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// First-class, menu-driven Group Chat Creator (pure create flow).
///
/// Launched from the sidebar "Create Group" button.
/// Uses the exact same linear step wizard UI (top-bar dots, currentStep,
/// AnimatedSwitcher, nav buttons) as create_character_page.dart.
/// Edit flows now use the dedicated tabbed EditGroupPage (matching EditCharacterPage style).
class CreateGroupChatPage extends StatefulWidget {
  const CreateGroupChatPage({super.key});

  @override
  State<CreateGroupChatPage> createState() => _CreateGroupChatPageState();
}

class _CreateGroupChatPageState extends State<CreateGroupChatPage> {
  final _draft = GroupWizardDraft();

  late final _actions = GroupWizardActions(
    showSnack: _showSnack,
    createGroup: _createGroup,
    generateScenario: _generateScenario,
    generateFirstMessage: _generateFirstMessage,
  );

  @override
  void initState() {
    super.initState();
    _draft.addListener(_onDraftChanged);
  }

  @override
  void dispose() {
    _draft.removeListener(_onDraftChanged);
    _draft.dispose();
    super.dispose();
  }

  void _onDraftChanged() {
    if (mounted) setState(() {});
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ── AI GENERATION ──────────────────────────────────────────────────

  /// The active LLM service, or null (after a snackbar) when not ready.
  LLMService? _readyService() {
    final llm = Provider.of<LLMProvider>(context, listen: false);
    final service = llm.activeService;
    if (!service.isReady) {
      _showSnack(
        'LLM backend is not ready. Start KoboldCPP or configure your API first.',
      );
      return null;
    }
    return service;
  }

  Future<void> _generateScenario({String dynamicsContext = ''}) async {
    final service = _readyService();
    if (service == null) return;
    _draft.update(() => _draft.isGeneratingScenario = true);
    try {
      final result = await GroupOpeningGenerator(
        service,
      ).scenario(members: _draft.members, dynamicsContext: dynamicsContext);
      if (result.isNotEmpty) {
        _draft.scenarioController.text = result;
      }
    } catch (e) {
      _showSnack('Scenario generation failed: $e');
    } finally {
      if (mounted) _draft.update(() => _draft.isGeneratingScenario = false);
    }
  }

  Future<void> _generateFirstMessage({String dynamicsContext = ''}) async {
    final service = _readyService();
    if (service == null) return;
    _draft.update(() => _draft.isGeneratingFirst = true);
    try {
      final result = await GroupOpeningGenerator(service).firstMessage(
        members: _draft.members,
        scenario: _draft.scenarioController.text,
        isDirector: _draft.directorMode,
        dynamicsContext: dynamicsContext,
      );
      if (result.isNotEmpty) {
        _draft.firstMessageController.text = result;
      }
    } catch (e) {
      _showSnack('First message generation failed: $e');
    } finally {
      if (mounted) _draft.update(() => _draft.isGeneratingFirst = false);
    }
  }

  // ── COMMIT ─────────────────────────────────────────────────────────

  /// Persist the new group and optionally open the chat.
  Future<void> _createGroup({bool enterChat = true}) async {
    if (_draft.members.length < 2) {
      _showSnack('A group needs at least 2 characters.');
      _draft.goToStep(0);
      return;
    }
    final name = _draft.nameController.text.trim();
    if (name.isEmpty) {
      _showSnack('Please give the group a name.');
      _draft.goToStep(1);
      return;
    }

    final repo = Provider.of<CharacterRepository>(context, listen: false);
    final groupRepo = Provider.of<GroupChatRepository>(context, listen: false);
    Provider.of<TtsService>(
      context,
      listen: false,
    ); // voices already resolved earlier
    final storage = Provider.of<StorageService>(context, listen: false);
    // The live database, not the startup snapshot `Provider<AppDatabase>`
    // holds: a backup restore closes that one.
    final database = liveDatabase(context);

    final group = await GroupChatCommitter(
      repo: repo,
      groupRepo: groupRepo,
      storage: storage,
      database: database,
    ).commit(_draft, name);

    if (enterChat) {
      // Full "Create & Enter" path.
      final chatService = Provider.of<ChatService>(context, listen: false);
      await chatService.setActiveGroup(group, groupRepo: groupRepo);
      await chatService.startNewChat();

      if (mounted) {
        Navigator.of(
          context,
        ).pushReplacement(MaterialPageRoute(builder: (_) => const ChatPage()));
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Group "$name" created!')));
      }
    } else {
      // "Create Only (don't enter chat yet)"
      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
        messenger.showSnackBar(
          SnackBar(content: Text('Group "$name" created.')),
        );
        Navigator.of(context).pop();
      }
    }
  }

  // ── BUILD ──────────────────────────────────────────────────────────

  /// The AnimatedSwitcher's direct child. Every step keeps today's shape —
  /// an unkeyed [SingleChildScrollView] (or [Center] for the disabled
  /// Dynamics notice) — so the switcher still updates in place between
  /// steps instead of cross-fading, and the scroll position carries over.
  Widget _buildStep() {
    final d = _draft;
    final a = _actions;
    Widget scroll(Widget child, {double padding = 32}) =>
        SingleChildScrollView(padding: EdgeInsets.all(padding), child: child);
    return switch (d.currentStep) {
      0 => scroll(GroupMembersStep(draft: d, actions: a), padding: 24),
      1 => scroll(GroupIdentityStep(draft: d, actions: a)),
      2 => scroll(GroupPromptsStep(draft: d, actions: a)),
      3 => scroll(GroupLoreStep(draft: d, actions: a)),
      4 => scroll(GroupRealismStep(draft: d, actions: a)),
      5 =>
        d.members.length <= 4
            ? scroll(GroupDynamicsStep(draft: d, actions: a))
            : Center(
                child: GroupDynamicsDisabledNotice(
                  memberCount: d.members.length,
                ),
              ),
      6 => scroll(GroupOpeningStep(draft: d, actions: a)),
      _ => scroll(GroupReviewStep(draft: d, actions: a)),
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundOf(context),
      appBar: AppBar(
        backgroundColor: AppColors.surfaceOf(context),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Row(
          children: [
            const Icon(
              Icons.group_add,
              color: AppColors.formMasterAccent,
              size: 22,
            ),
            const SizedBox(width: 10),
            const Text('Create Group Chat'),
            const Spacer(),
            GroupWizardStepIndicator(
              currentStep: _draft.currentStep,
              memberCount: _draft.members.length,
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: GroupTokenBadge(estimate: _draft.contentTokenEstimate),
          ),
        ],
      ),
      body: Stack(
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: _buildStep(),
          ),
        ],
      ),
    );
  }
}
