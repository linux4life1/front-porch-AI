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

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/pages/story_dashboard_page.dart';
import 'package:front_porch_ai/ui/story_setup/story_setup.dart';
import 'package:front_porch_ai/ui/story_studio/story_studio.dart';
import 'package:front_porch_ai/ui/theme/studio_colors.dart';

/// New Story (sketches I–L): Idea → Cast → Shape → Engine, with a summary
/// rail that fills in as you go. The project row is created on the first
/// Next and saved after every step, so backing out keeps the draft and the
/// shelf shows where it stopped. With [projectId] it reopens an existing
/// story's setup (the studio's "Setup" button); with [fromChat] it starts
/// at Idea with that chat already chosen.
class StorySetupPage extends StatefulWidget {
  final String? projectId;
  final StoryChatSource? fromChat;

  const StorySetupPage({super.key, this.projectId, this.fromChat});

  @override
  State<StorySetupPage> createState() => _StorySetupPageState();
}

class _StorySetupPageState extends State<StorySetupPage> {
  final _draft = StorySetupDraft();
  int _step = 0;
  int _reached = 0;
  String? _projectId;
  bool _saving = false;

  static const _stepLabels = ['Idea', 'Cast', 'Shape', 'Engine'];

  /// Decided once at load: an existing, finished story is being edited; a
  /// draft resumed from the shelf is still a new story.
  late final bool _editing;

  StoryProject? get _project {
    final id = _projectId;
    if (id == null) return null;
    return Provider.of<StoryRepository>(context, listen: false).getById(id);
  }

  @override
  void initState() {
    super.initState();
    _projectId = widget.projectId;
    final project = _project;
    _editing =
        project != null &&
        project.setupStep == null &&
        project.concept.trim().isNotEmpty;
    if (project != null) {
      _draft.loadFrom(
        project,
        Provider.of<CharacterRepository>(context, listen: false),
      );
      final resume = project.setupStep;
      if (resume != null && project.concept.trim().isEmpty) {
        _step = resume.clamp(0, _stepLabels.length - 1);
      }
      _reached = project.concept.trim().isEmpty
          ? _step
          : _stepLabels.length - 1;
    }
    final chat = widget.fromChat;
    if (chat != null) _draft.adoptChat(chat);
  }

  @override
  void dispose() {
    _draft.dispose();
    super.dispose();
  }

  bool get _narrow => MediaQuery.of(context).size.width < 760;

  /// Phones get a fifth "Ready?" screen in place of the rail.
  int get _stepCount => _stepLabels.length + (_narrow ? 1 : 0);

  @override
  Widget build(BuildContext context) {
    return StudioTheme(
      child: Scaffold(
        backgroundColor: StudioColors.bgOf(context),
        body: Column(
          children: [
            _header(context),
            Expanded(
              child: _narrow
                  ? _stepBody(context)
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: _stepBody(context)),
                        SetupRail(draft: _draft, step: _step),
                      ],
                    ),
            ),
            _footer(context),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
    decoration: BoxDecoration(
      color: StudioColors.sideOf(context),
      border: Border(bottom: BorderSide(color: StudioColors.lineOf(context))),
    ),
    child: Row(
      children: [
        StoryIconButton(
          Icons.arrow_back,
          tooltip: 'Back to stories',
          onPressed: _leave,
        ),
        const SizedBox(width: 6),
        Text(
          _editing ? 'Setup' : 'New story',
          style: StudioType.ui(context, size: 15, weight: FontWeight.w700),
        ),
        const SizedBox(width: 10),
        Text(
          _step < _stepLabels.length ? _stepLabels[_step] : 'Ready?',
          style: StudioType.ui(
            context,
            size: 12.5,
            color: StudioColors.mutedOf(context),
          ),
        ),
        const Spacer(),
        if (!_narrow)
          StoryStepDots(
            steps: _stepLabels,
            current: _step,
            onTap: (i) {
              if (i <= _reached) setState(() => _step = i);
            },
          ),
      ],
    ),
  );

  Widget _stepBody(BuildContext context) {
    final Widget body = switch (_step) {
      0 => IdeaStep(draft: _draft, onChanged: _changed),
      1 => CastStep(draft: _draft, onChanged: _changed),
      2 => ShapeStep(draft: _draft, onChanged: _changed),
      3 => EngineStep(draft: _draft, onChanged: _changed),
      _ => SetupRail(draft: _draft, step: _step, asPage: true),
    };
    return SingleChildScrollView(
      key: ValueKey('story-setup-step-$_step'),
      padding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820),
        child: body,
      ),
    );
  }

  Widget _footer(BuildContext context) {
    final last = _step == _stepCount - 1;
    final next = last
        ? (_editing ? 'Save changes' : 'Build the story bible')
        : 'Next: ${_step + 1 < _stepLabels.length ? _stepLabels[_step + 1] : 'Ready?'}';
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: BoxDecoration(
        color: StudioColors.sideOf(context),
        border: Border(top: BorderSide(color: StudioColors.lineOf(context))),
      ),
      child: Row(
        children: [
          StoryButton.ghost(
            _step == 0 ? 'Cancel' : 'Back',
            key: const ValueKey('story-setup-back'),
            onPressed: _step == 0 ? _leave : _back,
          ),
          const Spacer(),
          if (_narrow) ...[
            Text(
              '${_step + 1} of $_stepCount',
              style: StudioType.ui(
                context,
                size: 12,
                color: StudioColors.mutedOf(context),
              ),
            ),
            const SizedBox(width: 12),
          ],
          StoryButton.primary(
            next,
            key: const ValueKey('story-setup-next'),
            onPressed: _saving ? null : _next,
          ),
        ],
      ),
    );
  }

  void _changed() => setState(() {});

  Future<void> _back() async {
    await _save(step: _step - 1);
    if (mounted) setState(() => _step--);
  }

  Future<void> _leave() async {
    // Nothing typed yet: nothing to keep.
    if (_projectId == null) {
      Navigator.of(context).pop();
      return;
    }
    await _save(step: _step);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _next() async {
    if (_step == 0 && _draft.conceptController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Say what the story is first.')),
      );
      return;
    }
    if (_step < _stepCount - 1) {
      await _save(step: _step + 1);
      if (!mounted) return;
      setState(() {
        _step++;
        if (_step > _reached) _reached = _step;
      });
      return;
    }
    await _finish();
  }

  /// Create the row on the first Next; save the draft after every step.
  Future<void> _save({required int step}) async {
    if (_saving) return;
    _saving = true;
    try {
      final repo = Provider.of<StoryRepository>(context, listen: false);
      final charRepo = Provider.of<CharacterRepository>(context, listen: false);
      final persona = Provider.of<UserPersonaService>(context, listen: false);
      var project = _project;
      if (project == null) {
        project = await repo.createProject();
        _projectId = project.dbId;
      }
      _draft.applyTo(project, charRepo, persona);
      if (!_editing) project.setupStep = step;
      await repo.saveProject(project);
    } finally {
      _saving = false;
    }
  }

  Future<void> _finish() async {
    final editing = _editing;
    await _save(step: _stepLabels.length);
    final project = _project;
    if (project == null || !mounted) return;
    project.setupStep = null;
    await Provider.of<StoryRepository>(
      context,
      listen: false,
    ).saveProject(project);
    if (!mounted) return;
    if (editing) {
      Navigator.of(context).pop();
      return;
    }
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => StoryDashboardPage(
          projectId: project.dbId!,
          autoRunStoryArchitect: true,
        ),
      ),
    );
  }
}
