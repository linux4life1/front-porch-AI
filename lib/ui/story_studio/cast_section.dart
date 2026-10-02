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

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/story_studio/studio_running_overlay.dart';
import 'package:front_porch_ai/ui/story_studio/studio_widgets.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

/// The portrait square: the story's own portrait, else the character card's
/// art for an imported character, else initials on a warm gradient.
class StoryPortrait extends StatelessWidget {
  final StoryCastMember member;
  final double size;

  const StoryPortrait(this.member, {super.key, this.size = 52});

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
    final file = path == null ? null : File(path);
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: size,
        height: size,
        child: file != null
            ? Image.file(
                file,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _initials(context),
              )
            : _initials(context),
      ),
    );
  }

  Widget _initials(BuildContext context) => Container(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [
          AppColors.porchTerracottaOf(context).withValues(alpha: 0.55),
          AppColors.surfaceContainerOf(context),
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
    ),
    alignment: Alignment.center,
    child: Text(
      member.name.isEmpty ? '?' : member.name[0],
      style: TextStyle(
        color: AppColors.textPrimary(context),
        fontSize: size * 0.4,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

/// Cast dossiers: portrait, role, what drives them, their interview, their
/// read-along voice.
class CastSection extends StatelessWidget {
  final StoryProject project;
  final StoryPipelineService pipeline;

  const CastSection({super.key, required this.project, required this.pipeline});

  @override
  Widget build(BuildContext context) {
    if (pipeline.isRunning) return StudioRunningOverlay(pipeline);
    if (project.cast.isEmpty) {
      return Center(
        child: Text(
          'No cast yet — the story bible creates it.',
          style: TextStyle(color: AppColors.textSecondary(context)),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final member in project.cast)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _CastCard(
              project: project,
              member: member,
              pipeline: pipeline,
            ),
          ),
      ],
    );
  }
}

class _CastCard extends StatelessWidget {
  final StoryProject project;
  final StoryCastMember member;
  final StoryPipelineService pipeline;

  const _CastCard({
    required this.project,
    required this.member,
    required this.pipeline,
  });

  Future<void> _save(BuildContext context) =>
      Provider.of<StoryRepository>(context, listen: false).saveProject(project);

  Future<void> _interview(BuildContext context) async {
    try {
      await pipeline.runCharacterInterview(project, member.name);
    } catch (e) {
      if (context.mounted) showAiErrorSnackBar(context, e);
    }
  }

  Future<void> _generatePortrait(BuildContext context) async {
    final igs = Provider.of<ImageGenService>(context, listen: false);
    final prompt = StoryPipelineStudioBible.portraitPrompt(project, member);
    try {
      final bytes = await igs.generateImage(prompt: prompt, isPortrait: true);
      final path = await igs.saveAvatarToDisk(
        bytes,
        characterName: member.name,
      );
      if (path == null) throw Exception('The image could not be saved.');
      member.portrait = path;
      if (context.mounted) await _save(context);
    } catch (e) {
      if (context.mounted) showAiErrorSnackBar(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final igs = Provider.of<ImageGenService>(context, listen: false);
    final studio = project.engineMode == StoryEngineMode.studio;
    final drive = [
      member.role.isEmpty ? 'Supporting' : member.role,
      if (member.desire.isNotEmpty) 'wants ${member.desire}',
      if (member.flaw.isNotEmpty) 'flaw: ${member.flaw}',
    ].join(' · ');
    final excerpt = member.interview.length > 420
        ? '${member.interview.substring(0, 420).trimRight()}…'
        : member.interview;
    return WarmCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              StoryPortrait(member),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      member.name,
                      style: TextStyle(
                        color: AppColors.textPrimary(context),
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    Text(
                      drive,
                      style: TextStyle(
                        color: AppColors.textTertiary(context),
                        fontSize: 12,
                      ),
                    ),
                    if (member.description.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          member.description,
                          style: TextStyle(
                            color: AppColors.textSecondary(context),
                            fontSize: 12.5,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                icon: Icon(
                  Icons.more_horiz,
                  color: AppColors.iconSecondary(context),
                ),
                color: AppColors.surfaceContainerOf(context),
                onSelected: (v) {
                  if (v == 'interview') _interview(context);
                  if (v == 'portrait') _generatePortrait(context);
                },
                itemBuilder: (_) => [
                  if (studio)
                    PopupMenuItem(
                      value: 'interview',
                      child: Text(
                        member.interview.isEmpty
                            ? 'Interview'
                            : 'Interview again',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  if (igs.isConfigured)
                    const PopupMenuItem(
                      value: 'portrait',
                      child: Text(
                        'Generate portrait',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                ],
              ),
            ],
          ),
          if (excerpt.isNotEmpty) ...[
            const SizedBox(height: 10),
            const StoryKeyLabel('From their interview'),
            const SizedBox(height: 4),
            Text(
              '“$excerpt”',
              style: TextStyle(
                color: AppColors.textSecondary(context),
                fontSize: 13,
                height: 1.55,
                fontFamily: 'serif',
              ),
            ),
            if (member.interview.length > 420)
              TextButton(
                onPressed: () => showWarmDialog<void>(
                  context,
                  title: '${member.name} — interview',
                  width: 560,
                  content: SizedBox(
                    height: 420,
                    child: SingleChildScrollView(
                      child: SelectableText(
                        member.interview,
                        style: TextStyle(
                          color: AppColors.textSecondary(context),
                          fontSize: 13.5,
                          height: 1.6,
                          fontFamily: 'serif',
                        ),
                      ),
                    ),
                  ),
                  actions: [warmDialogCancel(context, label: 'Close')],
                ),
                child: const Text('Read the whole interview'),
              ),
          ] else if (studio) ...[
            const SizedBox(height: 10),
            StoryQuietButton(
              'Interview ${member.name.split(' ').first}',
              icon: Icons.record_voice_over_outlined,
              onPressed: () => _interview(context),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              if ((member.voiceSample ?? '').isNotEmpty)
                StoryChip('Voice: ${_short(member.voiceSample!)}'),
              if ((member.details['secret'] ?? '').isNotEmpty)
                StoryChip(
                  'Secret: ${_short(member.details['secret']!)}',
                  tone: 'honey',
                ),
            ],
          ),
          const SizedBox(height: 8),
          _voicePicker(context),
        ],
      ),
    );
  }

  static String _short(String s) =>
      s.length > 40 ? '${s.substring(0, 40)}…' : s;

  Widget _voicePicker(BuildContext context) => Consumer<TtsService>(
    builder: (context, tts, _) {
      final voices = tts.activeVoices;
      if (voices.isEmpty) return const SizedBox.shrink();
      return Row(
        children: [
          Icon(
            Icons.record_voice_over,
            size: 14,
            color: AppColors.porchHoneyOf(context).withValues(alpha: 0.7),
          ),
          const SizedBox(width: 8),
          Text(
            'Read-along voice:',
            style: TextStyle(
              color: AppColors.textTertiary(context),
              fontSize: 12,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButton<String>(
              value: voices.any((v) => v.id == member.voiceModel)
                  ? member.voiceModel
                  : null,
              hint: Text(
                'Default narrator',
                style: TextStyle(
                  color: AppColors.textTertiary(context),
                  fontSize: 12,
                ),
              ),
              dropdownColor: AppColors.surfaceContainerOf(context),
              isExpanded: true,
              underline: Container(
                height: 1,
                color: AppColors.borderOf(context).withValues(alpha: 0.5),
              ),
              style: TextStyle(
                color: AppColors.textSecondary(context),
                fontSize: 12,
              ),
              items: [
                const DropdownMenuItem<String>(
                  value: null,
                  child: Text('Default narrator'),
                ),
                for (final v in voices)
                  DropdownMenuItem<String>(value: v.id, child: Text(v.name)),
              ],
              onChanged: (v) {
                member.voiceModel = v;
                _save(context);
              },
            ),
          ),
        ],
      );
    },
  );
}
