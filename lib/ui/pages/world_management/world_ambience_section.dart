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

import 'package:front_porch_ai/models/world.dart';
import 'package:front_porch_ai/services/chat/scene/scene_sound.dart';

import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'world_ambience_library.dart';
import 'world_edit_draft.dart';

/// Scene ambience block for the create/edit World dialog: a switch row
/// independent of climate (visible for roots AND places), then a picker over
/// the bundled per-place loops and a "what it sounds like" preview. The
/// weather overlay is deterministic and needs no per-world table: rain adds
/// rain over the place loop, a quiet sky plays the place loop alone.
///
/// The dropdown carries a `custom` entry once a sound is stored, so the
/// editor shows "Custom sound" instead of falling back to the first preset
/// after a reopen. "Sound library…" expands [WorldAmbienceLibraryPanel]
/// inline — stored sounds first, the file picker behind them.
class WorldAmbienceSection extends StatelessWidget {
  const WorldAmbienceSection({
    super.key,
    required this.draft,
    required this.setDialogState,
  });

  final WorldEditDraft draft;
  final StateSetter setDialogState;

  /// Sentinel dropdown value for "the user's own stored sound". Never a
  /// [ScenePlaceLoop] file stem, so the two paths cannot collide.
  static const String kCustomValue = 'custom';

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _draftSwitch(
          context,
          title: 'Scene ambience',
          subtitle:
              'Ambient background sound plays in chats set here — the '
              'place\'s own loop, with the weather layered over it.',
          value: draft.ambienceEnabled,
          onChanged: (v) => setDialogState(() {
            draft.ambienceEnabled = v;
            if (v && draft.ambience == null && draft.customAmbience == null) {
              draft.ambience = ScenePlaceLoop.values.first.file;
            }
          }),
        ),
        if (draft.ambienceEnabled) ...[
          const SizedBox(height: 8),
          _section(context),
        ],
      ],
    );
  }

  Widget _section(BuildContext context) {
    final selected =
        scenePlaceLoopFor(draft.ambience) ?? ScenePlaceLoop.values.first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Ambience',
          style: TextStyle(
            color: AppColors.textSecondary(context),
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'The room you are in plays this loop at every time of day; '
          'rain, storm, snow or fog adds its weather loop on top.',
          style: TextStyle(
            color: AppColors.textTertiary(context),
            fontSize: 11,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          key: const Key('world-ambience-picker'),
          // ignore: deprecated_member_use
          value: draft.customAmbience != null
              ? kCustomValue
              : (draft.ambience ?? ScenePlaceLoop.values.first.file),
          isExpanded: true,
          decoration: InputDecoration(
            filled: true,
            fillColor: AppColors.surfaceContainerOf(context),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
          ),
          dropdownColor: AppColors.surfaceOf(context),
          selectedItemBuilder: (_) => [
            for (final p in ScenePlaceLoop.values)
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  p.label,
                  style: TextStyle(
                    color: AppColors.textPrimary(context),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Custom sound',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppColors.textPrimary(context),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
          items: [
            for (final p in ScenePlaceLoop.values)
              DropdownMenuItem(
                value: p.file,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        p.label,
                        style: TextStyle(
                          color: AppColors.textPrimary(context),
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        kScenePlaceLoopFeel[p.file] ?? '',
                        style: TextStyle(
                          color: AppColors.textSecondary(context),
                          fontSize: 11,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            DropdownMenuItem(
              value: kCustomValue,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Custom sound…',
                      style: TextStyle(
                        color: AppColors.textPrimary(context),
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      draft.customAmbience ??
                          'Opens your sound library — your own MP3s, kept for every world',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: draft.customAmbience != null
                            ? AppColors.formAccentOf(context)
                            : AppColors.textSecondary(context),
                        fontSize: 11,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          onChanged: (v) {
            if (v == null) return;
            if (v == kCustomValue) {
              // The drawer, not a value: nothing changes until a sound in it
              // is picked (or a built-in loop chosen instead).
              setDialogState(() => draft.ambienceLibraryOpen = true);
              return;
            }
            setDialogState(() {
              draft.ambience = v;
              draft.customAmbience = null;
              draft.ambienceLibraryOpen = false;
            });
          },
        ),
        Builder(
          builder: (_) {
            final feel = kScenePlaceLoopFeel[selected.file] ?? '';
            return Container(
              margin: const EdgeInsets.only(top: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.formAccentOf(context).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: AppColors.formAccentOf(
                    context,
                  ).withValues(alpha: 0.22),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.music_note,
                        size: 16,
                        color: AppColors.formAccentOf(context),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'What it sounds like',
                        style: TextStyle(
                          color: AppColors.formAccentOf(context),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    draft.customAmbience != null
                        ? 'Your own sound — ${draft.customAmbience}'
                        : (feel.isEmpty ? selected.label : feel),
                    style: TextStyle(
                      color: AppColors.textPrimary(context),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        if (draft.ambienceLibraryOpen)
          WorldAmbienceLibraryPanel(
            key: const Key('world-ambience-library'),
            selected: draft.customAmbience,
            onPicked: (name) => setDialogState(() {
              draft.ambienceEnabled = true;
              draft.customAmbience = name;
              draft.ambience = null;
              draft.ambienceLibraryOpen = false;
            }),
            onDismiss: () =>
                setDialogState(() => draft.ambienceLibraryOpen = false),
          ),
      ],
    );
  }

  Widget _draftSwitch(
    BuildContext context, {
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: AppColors.textPrimary(context),
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  color: AppColors.textTertiary(context),
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
        Switch(
          value: value,
          activeThumbColor: AppColors.formAccentOf(context),
          onChanged: onChanged,
        ),
      ],
    );
  }
}

/// Copy the ambience draft onto a [World] before save, regardless of
/// [climateEnabled] — sound is not climate.
void applyAmbience(WorldEditDraft draft, World newWorld) {
  if (!draft.ambienceEnabled) {
    newWorld.ambience = null;
    newWorld.customAmbience = null;
    return;
  }
  newWorld.customAmbience = draft.customAmbience;
  newWorld.ambience = draft.customAmbience == null ? draft.ambience : null;
}
