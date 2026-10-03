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
import 'package:front_porch_ai/ui/story_studio/studio_buttons.dart';
import 'package:front_porch_ai/ui/story_studio/studio_cards.dart';
import 'package:front_porch_ai/ui/story_studio/studio_theme.dart';
import 'package:front_porch_ai/ui/story_studio/studio_widgets.dart';
import 'package:front_porch_ai/ui/theme/studio_colors.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

/// The portrait: the story's own, else the library card's art for a
/// character of the same name, else initials on the warm gradient.
class StoryPortrait extends StatelessWidget {
  final StoryCastMember member;
  final bool large;

  const StoryPortrait(this.member, {super.key, this.large = true});

  @override
  Widget build(BuildContext context) {
    final repo = Provider.of<CharacterRepository>(context, listen: false);
    final path =
        member.portrait ??
        repo.characters
            .where((c) => c.name == member.name)
            .map((c) => c.imagePath)
            .whereType<String>()
            .firstOrNull;
    return StoryAvatar(member.name, imagePath: path, large: large);
  }
}

/// Cast (sketch R): one dossier per character, add / edit / remove here so
/// the Cast step and this screen are the same list.
class CastSection extends StatefulWidget {
  final StoryProject project;
  final StoryPipelineService pipeline;

  const CastSection({super.key, required this.project, required this.pipeline});

  @override
  State<CastSection> createState() => _CastSectionState();
}

class _CastSectionState extends State<CastSection> {
  /// Names whose portrait is being painted right now.
  final Set<String> _painting = {};

  StoryProject get p => widget.project;

  Future<void> _save() =>
      Provider.of<StoryRepository>(context, listen: false).saveProject(p);

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 900;
    final cards = [for (final m in p.cast) _card(m)];
    return ListView(
      key: const ValueKey('studio-cast'),
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${p.cast.length} character${p.cast.length == 1 ? '' : 's'}',
                style: StudioType.ui(
                  context,
                  size: 12.5,
                  color: StudioColors.mutedOf(context),
                ),
              ),
            ),
            StoryButton(
              'Add character',
              key: const ValueKey('cast-add'),
              icon: Icons.add,
              onPressed: () => _edit(null),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (p.cast.isEmpty)
          const StoryEmptyState(
            title: 'No cast yet',
            detail: 'The story bible creates it, or add someone yourself.',
          )
        else if (wide)
          for (var i = 0; i < cards.length; i += 2) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: cards[i]),
                const SizedBox(width: 12),
                Expanded(
                  child: i + 1 < cards.length
                      ? cards[i + 1]
                      : const SizedBox.shrink(),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ]
        else
          for (final c in cards) ...[c, const SizedBox(height: 12)],
      ],
    );
  }

  Widget _card(StoryCastMember m) {
    final muted = StudioColors.mutedOf(context);
    final studio = p.engineMode == StoryEngineMode.studio;
    final running = widget.pipeline.isRunning;
    final igs = Provider.of<ImageGenService>(context, listen: false);
    final tts = Provider.of<TtsService>(context);
    final voices = tts.activeVoices;
    final voice = voices.where((v) => v.id == m.voiceModel).firstOrNull;
    final secret = m.details['secret'] ?? '';
    final meta = [
      if (m.role.isNotEmpty) m.role,
      if (m.desire.isNotEmpty) 'wants ${m.desire}',
      if (m.flaw.isNotEmpty) 'flaw: ${m.flaw}',
    ].join(' · ');
    return StoryCard(
      key: ValueKey('cast-${m.name}'),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            StoryPortrait(m),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    m.name,
                    style: StudioType.ui(context, weight: FontWeight.w700),
                  ),
                  if (meta.isNotEmpty)
                    Text(
                      meta,
                      style: StudioType.ui(context, size: 12, color: muted),
                    ),
                  if (m.description.isNotEmpty)
                    Text(
                      m.description,
                      style: StudioType.ui(context, size: 12.5),
                    ),
                ],
              ),
            ),
            StoryMenuButton(
              key: ValueKey('cast-menu-${m.name}'),
              entries: [
                StoryMenuEntry(
                  m.interview.isEmpty ? 'Interview' : 'Interview again…',
                  enabled: studio && !running,
                  onSelect: () => _interview(m),
                ),
                StoryMenuEntry(
                  'Generate portrait',
                  enabled: igs.isConfigured && !_painting.contains(m.name),
                  onSelect: () => _paint(m),
                ),
                StoryMenuEntry('Edit…', onSelect: () => _edit(m)),
                StoryMenuEntry(
                  'Remove from cast…',
                  danger: true,
                  divider: true,
                  onSelect: () => _remove(m),
                ),
              ],
            ),
          ],
        ),
        if (m.interview.isNotEmpty) ...[
          const StoryKeyLabel('From their interview'),
          Text(
            '“${_excerpt(m.interview)}”',
            style: StudioType.prose(context, size: 13.5),
          ),
          StoryButton.ghost(
            'Read the whole interview',
            onPressed: () => showStoryDialog<void>(
              context,
              title: '${m.name}, interviewed',
              width: 560,
              body: Text(
                m.interview,
                style: StudioType.prose(context, size: 13.5),
              ),
              actions: (ctx) => [
                StoryButton.ghost('Close', onPressed: () => Navigator.pop(ctx)),
              ],
            ),
          ),
        ] else if (studio)
          Row(
            children: [
              StoryButton(
                'Interview ${m.name.split(' ').first}',
                key: ValueKey('cast-interview-${m.name}'),
                onPressed: running ? null : () => _interview(m),
              ),
              const SizedBox(width: 8),
              if (igs.isConfigured && m.portrait == null)
                StoryButton.ghost(
                  'Generate portrait',
                  onPressed: _painting.contains(m.name)
                      ? null
                      : () => _paint(m),
                ),
              if (_painting.contains(m.name)) ...[
                const SizedBox(width: 8),
                const StoryChip('● painting portrait', tone: 'amber'),
              ],
            ],
          ),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            if ((m.voiceSample ?? '').isNotEmpty)
              StoryChip('Voice: ${_short(m.voiceSample!)}'),
            if (secret.isNotEmpty)
              StoryChip('Secret: ${_short(secret)}', tone: 'honey'),
            if (_painting.contains(m.name) && m.interview.isNotEmpty)
              const StoryChip('● painting portrait', tone: 'amber'),
          ],
        ),
        if (voices.isNotEmpty)
          Row(
            children: [
              Text(
                'Reads aloud as',
                style: StudioType.ui(context, size: 12, color: muted),
              ),
              const SizedBox(width: 8),
              StoryChip(
                voice == null ? 'Default narrator' : voice.name,
                key: ValueKey('cast-voice-${m.name}'),
                onTap: () => _pickVoice(m, voices),
              ),
            ],
          ),
      ],
    );
  }

  static String _short(String s) =>
      s.length > 40 ? '${s.substring(0, 40)}…' : s;

  static String _excerpt(String s) =>
      s.length > 420 ? '${s.substring(0, 420)}…' : s;

  Future<void> _interview(StoryCastMember m) async {
    if (m.interview.isNotEmpty) {
      final ok = await showStoryConfirm(
        context,
        title: 'Interview ${m.name} again?',
        body: 'The current interview is replaced; the voice guide follows it.',
        confirmLabel: 'Interview',
      );
      if (!ok) return;
    }
    try {
      await widget.pipeline.runCharacterInterview(p, m.name);
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) showAiErrorSnackBar(context, e);
    }
  }

  Future<void> _paint(StoryCastMember m) async {
    final igs = Provider.of<ImageGenService>(context, listen: false);
    final prompt = StoryPipelineStudioBible.portraitPrompt(p, m);
    setState(() => _painting.add(m.name));
    try {
      final bytes = await igs.generateImage(prompt: prompt, isPortrait: true);
      final path = await igs.saveAvatarToDisk(bytes, characterName: m.name);
      if (path == null) throw Exception('The image could not be saved.');
      m.portrait = path;
      await _save();
    } catch (e) {
      if (mounted) showAiErrorSnackBar(context, e);
    } finally {
      if (mounted) setState(() => _painting.remove(m.name));
    }
  }

  Future<void> _pickVoice(StoryCastMember m, List<TtsVoiceInfo> voices) async {
    final picked = await showStoryDialog<String>(
      context,
      title: 'Reads aloud as',
      width: 420,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final v in [null, ...voices])
            InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () => Navigator.pop(context, v?.id ?? ''),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        v == null ? 'Default narrator' : v.name,
                        style: StudioType.ui(
                          context,
                          weight: (v?.id ?? '') == (m.voiceModel ?? '')
                              ? FontWeight.w700
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                    if (v != null)
                      Text(
                        v.engine,
                        style: StudioType.ui(
                          context,
                          size: 12,
                          color: StudioColors.mutedOf(context),
                        ),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
      actions: (ctx) => [
        StoryButton.ghost('Cancel', onPressed: () => Navigator.pop(ctx)),
      ],
    );
    if (picked == null || !mounted) return;
    m.voiceModel = picked.isEmpty ? null : picked;
    await _save();
    setState(() {});
  }

  Future<void> _edit(StoryCastMember? m) async {
    final name = TextEditingController(text: m?.name ?? '');
    final role = TextEditingController(text: m?.role ?? '');
    final desc = TextEditingController(text: m?.description ?? '');
    final desire = TextEditingController(text: m?.desire ?? '');
    final flaw = TextEditingController(text: m?.flaw ?? '');
    final ok = await showStoryDialog<bool>(
      context,
      title: m == null ? 'Add character' : 'Edit ${m.name}',
      width: 480,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          StoryField(controller: name, hint: 'Name'),
          const SizedBox(height: 8),
          StoryField(controller: role, hint: 'Role (Protagonist, Mentor…)'),
          const SizedBox(height: 8),
          StoryTextArea(controller: desc, hint: 'Who they are', minLines: 3),
          const SizedBox(height: 8),
          StoryField(controller: desire, hint: 'What they want'),
          const SizedBox(height: 8),
          StoryField(controller: flaw, hint: 'Their flaw'),
        ],
      ),
      actions: (ctx) => [
        StoryButton.ghost('Cancel', onPressed: () => Navigator.pop(ctx, false)),
        StoryButton.primary(
          m == null ? 'Add' : 'Save',
          onPressed: () => Navigator.pop(ctx, true),
        ),
      ],
    );
    if (ok != true || !mounted || name.text.trim().isEmpty) return;
    final target =
        m ?? StoryCastMember(name: name.text.trim(), role: '', description: '');
    target
      ..name = name.text.trim()
      ..role = role.text.trim()
      ..description = desc.text.trim()
      ..desire = desire.text.trim()
      ..flaw = flaw.text.trim();
    if (m == null) p.cast.add(target);
    await _save();
    setState(() {});
  }

  Future<void> _remove(StoryCastMember m) async {
    final ok = await showStoryConfirm(
      context,
      title: 'Remove ${m.name} from the cast?',
      body:
          'Their dossier, interview and relationships are removed. Scenes '
          'already written keep their text.',
      confirmLabel: 'Remove',
      destructive: true,
    );
    if (!ok || !mounted) return;
    p.cast.remove(m);
    p.relationships.removeWhere((r) => r.from == m.name || r.to == m.name);
    await _save();
    setState(() {});
  }
}
