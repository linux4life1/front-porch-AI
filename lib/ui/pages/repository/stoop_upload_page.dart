// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// The Drift schema also declares a `World` row class — hide it so `World`
// below always means the model (the same shape .fpworld export uses).
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/backporch/backporch.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/pages/repository/stoop_adult_lock_banner.dart';
import 'package:front_porch_ai/ui/pages/repository/stoop_glass.dart';
import 'package:front_porch_ai/ui/pages/repository/stoop_verify_banner.dart';
import 'package:front_porch_ai/ui/pages/repository/stoop_pick_step.dart';
import 'package:front_porch_ai/ui/pages/repository/stoop_upload/stoop_upload.dart';
import 'package:front_porch_ai/ui/pages/repository/stoop_wizard_steps.dart';

/// Wizard to share one of the user's local characters to The Stoop. Mirrors the
/// app's create-wizard chrome (step dots + AnimatedSwitcher + nav buttons).
/// Pops `true` once a card has been submitted for review.
class StoopUploadPage extends StatefulWidget {
  /// When set, the wizard runs in UPDATE mode: it is locked to this local
  /// character OR group (the Pick step is skipped) and publishes a new version
  /// of the existing Stoop post [updateStoopId] IN PLACE, instead of creating a
  /// new one. Exactly one of [updateCharacter] / [updateGroup] is set in update
  /// mode.
  final CharacterCard? updateCharacter;
  final GroupChat? updateGroup;
  final String? updateStoopId;

  /// The posted card's current NSFW flag, so update mode preserves it by default.
  final bool initialNsfw;

  /// The posted card's current "Original creator" credit, so update mode
  /// preserves it by default (clearing the field on update removes the credit).
  final String? initialOriginalCreator;

  /// The posted card's current Discussion opt-in (client-side / future hub
  /// field `commentsEnabled`). Default off.
  final bool initialCommentsEnabled;

  /// The post's current DISPLAY name + summary, so update mode preserves them
  /// instead of re-seeding from the local card. The display name is the
  /// listing title ("Misty Meadows, Misguided Meteorologist") and may differ
  /// from the card's in-chat name ("Misty", what {{char}} maps to) — without
  /// these, publishing an update would silently revert a custom title.
  final String? initialName;
  final String? initialSummary;

  const StoopUploadPage({
    super.key,
    this.updateCharacter,
    this.updateGroup,
    this.updateStoopId,
    this.initialNsfw = false,
    this.initialOriginalCreator,
    this.initialName,
    this.initialSummary,
    this.initialCommentsEnabled = false,
  });

  bool get isUpdate =>
      updateStoopId != null && (updateCharacter != null || updateGroup != null);

  @override
  State<StoopUploadPage> createState() => _StoopUploadPageState();
}

class _StoopUploadPageState extends State<StoopUploadPage> {
  static const _steps = ['Pick', 'Details', 'Content', 'Review'];

  /// The Stoop shows at most this many tags per card; cards with more are
  /// trimmed and the creator picks which ones to keep.
  static const _maxTags = 20;

  int _currentStep = 0;
  CharacterCard? _selected;
  GroupChat? _selectedGroup; // set instead of _selected when sharing a group
  World? _selectedWorld; // set when sharing a place (.fpworld) — see below

  /// [_selectedGroup]'s cast once it has loaded (null until then). Members live
  /// in their own table, not on GroupChat, so the 18+ scan needs an async read.
  List<GroupMember>? _groupMembers;
  final _name = TextEditingController();
  final _summary = TextEditingController();
  final _originalCreator = TextEditingController();
  final _tagInput = TextEditingController();

  /// Every candidate tag (the card's own, plus any the creator types).
  List<String> _tagPool = [];

  /// The subset (≤ [_maxTags]) that will actually be published.
  List<String> _tags = [];

  /// The 18+ flag AND who set it (author vs the intimate-preferences rule), so
  /// changing the pick withdraws a forced tick without touching the author's.
  final _adult = StoopAdultFlag();
  bool _commentsEnabled = false;
  bool _standardsAck = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _summary.dispose();
    _originalCreator.dispose();
    _tagInput.dispose();
    super.dispose();
  }

  // Prefill the summary from free text, trimming at a word boundary (+ ellipsis)
  // when it's over the 280-char field instead of chopping mid-word.
  void _setSummaryFrom(String text) {
    final desc = text.trim();
    if (desc.length <= 280) {
      _summary.text = desc;
    } else {
      var cut = desc.substring(0, 279);
      final lastSpace = cut.lastIndexOf(' ');
      if (lastSpace > 200) cut = cut.substring(0, lastSpace);
      _summary.text = '${cut.trimRight()}…';
    }
  }

  void _selectGroup(GroupChat group) {
    setState(() => _applyGroupSelection(group));
  }

  // Pre-fills the wizard from a chosen group. No setState of its own — safe to
  // call from initState and from _selectGroup; the member load setStates itself.
  void _applyGroupSelection(GroupChat group) {
    _selectedGroup = group;
    _selected = null;
    _selectedWorld = null;
    _name.text = group.name;
    _setSummaryFrom(
      group.scenario,
    ); // groups have no description; seed scenario
    _tagPool = [];
    _tags = [];
    // The cast lives in group_members, so the 18+ scan can't be synchronous.
    // Keyed by id on the way back so a slow first pick can't overwrite a second.
    // ADVISORY ONLY: this read feeds the banner and the switch, because the
    // wizard has to show something before Submit. The published flag is decided
    // in StoopUploadPublisher from the card it actually uploads — this query hides its
    // own failures behind an empty list, which reads as "clean cast".
    _groupMembers = null;
    _adult.reconcile(forced: false); // no cast known yet
    context.read<GroupChatRepository>().getMembersForGroup(group.id).then((m) {
      if (!mounted || _selectedGroup?.id != group.id) return;
      setState(() {
        _groupMembers = m;
        _adult.reconcile(forced: _forcedAdult);
      });
    });
  }

  @override
  void initState() {
    super.initState();
    // Update mode: lock to the given character OR group and skip the Pick step.
    final uc = widget.updateCharacter;
    final ug = widget.updateGroup;
    // The seed goes FIRST so the appliers' 18+ force lands on top of it: a card
    // posted before that rule carries initialNsfw == false, and re-publishing
    // it must not preserve that.
    if (uc != null) {
      _adult.setByAuthor(
        widget.initialNsfw,
      ); // the post's own flag, not the rule
      _applySelection(uc);
      _currentStep = 1;
    } else if (ug != null) {
      _adult.setByAuthor(widget.initialNsfw);
      _applyGroupSelection(ug); // group force lands when the members do
      _currentStep = 1;
    }
    // Update mode: the post's stored display name/summary win over the
    // card-derived seeds the appliers just set (custom titles must survive).
    if (widget.initialName?.trim().isNotEmpty ?? false) {
      _name.text = widget.initialName!.trim();
    }
    if (widget.initialSummary?.trim().isNotEmpty ?? false) {
      _summary.text = widget.initialSummary!.trim();
    }
    _originalCreator.text = widget.initialOriginalCreator ?? '';
    // Per-card Discussion opt-in. Default OFF. Update mode restores the
    // published choice from the client store (or the card field).
    if (widget.updateStoopId != null) {
      _commentsEnabled = StoopCommentsOptIn.instance.published(
        widget.updateStoopId!,
        fromCard: widget.initialCommentsEnabled,
      );
    } else {
      _commentsEnabled = widget.initialCommentsEnabled;
    }
  }

  void _select(CharacterCard card) {
    setState(() => _applySelection(card));
  }

  // Pre-fills the wizard from a chosen character. No setState — safe to call from
  // initState (update mode) and from _select (wrapped in setState).
  void _applySelection(CharacterCard card) {
    _selected = card;
    _selectedGroup = null;
    _groupMembers = null;
    _selectedWorld = null;
    // Intimate preferences force 18+ — and picking something else withdraws
    // that force again (the author's own tick survives; see StoopAdultFlag).
    _adult.reconcile(forced: _forcedAdult);
    _name.text = card.name;
    _setSummaryFrom(card.description);
    // De-duplicate (preserving order) into the candidate pool, then
    // pre-select the first [_maxTags]; the creator can re-pick on the step.
    final seen = <String>{};
    final pool = <String>[];
    for (final t in card.tags) {
      final tt = t.trim();
      if (tt.isNotEmpty && seen.add(tt)) pool.add(tt);
    }
    _tagPool = pool;
    _tags = pool.take(_maxTags).toList();
  }

  /// Live checklist for the currently selected card/group/world (sync for
  /// solo; worlds use the repo envelope when available).
  StoopCompleteness? _selectedCompleteness() {
    final card = _selected;
    if (card != null) {
      return StoopCardCompleteness.assess(card.toJson(), 'SOLO');
    }
    final group = _selectedGroup;
    if (group != null) {
      // Group-level fields only here. Member substance is validated in
      // StoopUploadPublisher after GroupCardExporter builds the portable payload
      // (membership lives in group_members, not on GroupChat).
      return StoopCardCompleteness.assess({
        'name': group.name,
        'first_message': group.firstMessage,
        'scenario': group.scenario,
        'system_prompt': group.systemPrompt,
        'members': const [
          {'name': '_', 'description': '_'},
        ],
      }, 'GROUP');
    }
    final world = _selectedWorld;
    if (world != null) {
      // Prefer the same .fpworld envelope the publish path sends.
      try {
        final repo = context.read<WorldRepository>();
        final envelope = repo.fpWorldJson(world);
        return StoopCardCompleteness.assess(envelope, 'WORLD');
      } catch (_) {
        return StoopCardCompleteness.assess({
          'name': world.name,
          'biome': const <String, dynamic>{},
        }, 'WORLD');
      }
    }
    return null;
  }

  /// True when the pick carries intimate preferences, which force the 18+ flag
  /// on. Banner and locked switch read THIS one getter — a second copy of the
  /// rule would drift. A place has no cast, so never.
  ///
  /// The GROUP publish path deliberately re-derives it from the built card
  /// instead (see [StoopUploadPublisher]): this getter depends on a separate read that
  /// can come back empty on a database hiccup.
  bool get _forcedAdult => stoopForcesAdult(_selected, _groupMembers);

  /// A group is picked but its cast hasn't arrived, so the rule's answer isn't
  /// known yet. Update mode opens straight onto the Content step, so without
  /// this the switch's first frames claim "unlocked, all-ages" and then snap.
  bool get _castPending => _selectedGroup != null && _groupMembers == null;

  // Pre-fills the wizard from a chosen place. Mirrors the character/group
  // appliers above (each type builds a different payload chain, so unifying
  // the three would just braid unrelated field wiring together).
  void _applyWorldSelection(World world) {
    _selectedWorld = world;
    _selected = null;
    _selectedGroup = null;
    _groupMembers = null;
    // A place has no cast at all, so any force in effect is now released.
    _adult.reconcile(forced: false);
    _name.text = world.name;
    _setSummaryFrom(world.description);
    _tagPool = [];
    _tags = [];
  }

  bool get _canAdvance {
    switch (_currentStep) {
      case 0:
        return _selected != null ||
            _selectedGroup != null ||
            _selectedWorld != null;
      case 1:
        return _name.text.trim().isNotEmpty && _summary.text.trim().isNotEmpty;
      case 2:
        // Standards ack + definition completeness (no empty first_mes shells).
        final comp = _selectedCompleteness();
        return _standardsAck && !(comp?.incomplete ?? false);
      case 3:
        final comp = _selectedCompleteness();
        return !(comp?.incomplete ?? false);
      default:
        return true;
    }
  }

  void _next() {
    if (!_canAdvance) return;
    if (_currentStep < _steps.length - 1) {
      setState(() => _currentStep++);
    } else {
      _publish();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: stoopBg0(context),
      appBar: AppBar(
        backgroundColor: stoopBg0(context),
        foregroundColor: stoopCream(context),
        elevation: 0,
        shape: Border(bottom: BorderSide(color: stoopBorder(context))),
        title: Text(
          widget.isUpdate ? 'Update character' : 'Share to The Stoop',
          style: stoopDisplay(context, size: 19),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: StoopWizardSteps(steps: _steps, current: _currentStep),
          ),
        ),
      ),
      body: Column(
        children: [
          // Say it before they fill the whole wizard and hit a 403 at the end.
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: StoopVerifyBanner(),
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: _stepBody(),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _navButtons(),
    );
  }

  Widget _stepBody() {
    switch (_currentStep) {
      case 0:
        // Step 0 — pick a local character, group, or place. StoopPickStep is
        // folder-aware: the grids follow the home grid's folder hierarchy via
        // the shared buildFolderPickView rules.
        return StoopPickStep(
          selectedCard: _selected,
          selectedGroup: _selectedGroup,
          selectedWorldId: _selectedWorld?.id,
          onSelectCard: _select,
          onSelectGroup: _selectGroup,
          onSelectWorld: (w) => setState(() => _applyWorldSelection(w)),
        );
      case 1:
        return StoopUploadDetailsStep(
          selectedCharacterName: _selected?.name,
          name: _name,
          summary: _summary,
          originalCreator: _originalCreator,
          tagInput: _tagInput,
          tagPool: _tagPool,
          tags: _tags,
          maxTags: _maxTags,
          onChanged: () => setState(() {}),
          onToggleTag: _toggleTag,
          onAddTag: _addTag,
        );
      case 2:
        return StoopUploadContentStep(
          completeness: _selectedCompleteness(),
          forcedAdult: _forcedAdult,
          adultValue: _adult.value,
          castPending: _castPending,
          commentsEnabled: _commentsEnabled,
          standardsAck: _standardsAck,
          onAdultChanged: (v) => setState(() => _adult.setByAuthor(v)),
          onCommentsChanged: (v) => setState(() => _commentsEnabled = v),
          onStandardsAckChanged: (v) =>
              setState(() => _standardsAck = v ?? false),
        );
      default:
        return StoopUploadReviewStep(
          selectedCard: _selected,
          selectedGroup: _selectedGroup,
          selectedWorld: _selectedWorld,
          completeness: _selectedCompleteness(),
          name: _name.text.trim(),
          summary: _summary.text.trim(),
          originalCreator: _originalCreator.text.trim(),
          adultValue: _adult.value,
          forcedAdult: _forcedAdult,
          tags: _tags,
          error: _error,
        );
    }
  }

  void _toggleTag(String t) {
    setState(() => stoopUploadToggleTag(_tags, t, _maxTags));
  }

  void _addTag(String raw) {
    setState(
      () => stoopUploadAddTag(
        pool: _tagPool,
        tags: _tags,
        raw: raw,
        max: _maxTags,
      ),
    );
  }

  Future<void> _publish() {
    return StoopUploadPublisher(
      context: context,
      name: _name,
      summary: _summary,
      originalCreator: _originalCreator,
      adult: _adult,
      tags: _tags,
      commentsEnabled: _commentsEnabled,
      isUpdate: widget.isUpdate,
      updateStoopId: widget.updateStoopId,
      onStart: () => setState(() {
        _busy = true;
        _error = null;
      }),
      onError: (msg) => setState(() => _error = msg),
      onAdultForced: () => setState(() => _adult.reconcile(forced: true)),
      onIdle: () => setState(() => _busy = false),
    ).publish(card: _selected, group: _selectedGroup, world: _selectedWorld);
  }

  Widget _navButtons() {
    return StoopUploadNavBar(
      // In update mode the Pick step (0) is skipped, so Back stops at 1.
      showBack: _currentStep > (widget.isUpdate ? 1 : 0),
      isLast: _currentStep == _steps.length - 1,
      busy: _busy,
      canAdvance: _canAdvance,
      onBack: () => setState(() => _currentStep--),
      onNext: _next,
    );
  }
}
