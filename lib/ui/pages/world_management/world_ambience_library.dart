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

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/storage/user_audio_store.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

import 'world_ambience_audio.dart';

/// The inline custom-sound library inside the World editor's ambience
/// section: the MP3s already stored under `$rootPath/audio/`, newest
/// first, so one upload is reusable by every later world or place.
///
/// It is a panel, not a dialog — the editor is itself a dialog, and a
/// second modal on top of it both reads as slop and fights the theme.
/// The styling follows the ambience section's own vocabulary (the
/// "what it sounds like" card: tinted surface, accent hairline when a
/// pick is selected). Tapping a row assigns it; ▶ auditions it first.
/// The list is height-capped and scrolls, so a big library never takes
/// over the editor.
class WorldAmbienceLibraryPanel extends StatefulWidget {
  const WorldAmbienceLibraryPanel({
    super.key,
    required this.selected,
    required this.onPicked,
    required this.onDismiss,
  });

  /// The sound currently assigned, or null. Highlights its row.
  final String? selected;

  /// A stored sound was chosen (bare name under the audio dir).
  final ValueChanged<String> onPicked;

  /// Collapse the panel (Done, or ESC/close affordance).
  final VoidCallback onDismiss;

  /// List height cap: past a handful of rows it scrolls.
  static const double kMaxListHeight = 232;

  @override
  State<WorldAmbienceLibraryPanel> createState() =>
      _WorldAmbienceLibraryPanelState();
}

class _WorldAmbienceLibraryPanelState extends State<WorldAmbienceLibraryPanel> {
  List<({String name, int bytes, int modifiedMs})>? _sounds;
  String? _auditioning;
  AudioPlayer? _player;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final storage = Provider.of<StorageService>(context, listen: false);
    final sounds = await UserAudioStore.listUserAudio(storage);
    if (!mounted) return;
    setState(() => _sounds = sounds);
  }

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  Future<void> _audition(
    BuildContext context,
    ({String name, int bytes, int modifiedMs}) s,
  ) async {
    final storage = Provider.of<StorageService>(context, listen: false);
    if (_auditioning == s.name) {
      await _player?.stop();
      if (mounted) setState(() => _auditioning = null);
      return;
    }
    final path = p.join(storage.audioDir.path, s.name);
    final player = _player ??= AudioPlayer();
    try {
      await player.stop();
      await player.play(DeviceFileSource(path));
      if (mounted) setState(() => _auditioning = s.name);
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not play that file here.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final sounds = _sounds;
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerOf(context).withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: AppColors.borderOf(context).withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(
                'YOUR SOUNDS',
                style: TextStyle(
                  color: AppColors.textSecondary(context),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                key: const Key('world-ambience-library-import'),
                onPressed: () => _importFromFile(context),
                icon: const Icon(Icons.file_open_outlined, size: 15),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  foregroundColor: AppColors.formAccentOf(context),
                  textStyle: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                label: const Text('From a file…'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (sounds == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Center(
                child: SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else if (sounds.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                'Nothing stored yet. "From a file…" picks an MP3 once; '
                'after that it lives here for every world.',
                style: TextStyle(
                  color: AppColors.textTertiary(context),
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(
                maxHeight: WorldAmbienceLibraryPanel.kMaxListHeight,
              ),
              child: ListView.separated(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: sounds.length,
                separatorBuilder: (_, _) => const SizedBox(height: 6),
                itemBuilder: (context, i) => _row(context, sounds[i]),
              ),
            ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              key: const Key('world-ambience-library-done'),
              onPressed: widget.onDismiss,
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                foregroundColor: AppColors.textSecondary(context),
                textStyle: const TextStyle(fontSize: 12),
              ),
              child: const Text('Done'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(
    BuildContext context,
    ({String name, int bytes, int modifiedMs}) s,
  ) {
    final isSelected = widget.selected == s.name;
    final isPlaying = _auditioning == s.name;
    return InkWell(
      key: Key('world-ambience-library-row-${s.name}'),
      onTap: () => widget.onPicked(s.name),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.formAccentOf(context).withValues(alpha: 0.10)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? AppColors.formAccentOf(context)
                : AppColors.borderOf(context).withValues(alpha: 0.4),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            InkWell(
              key: Key('world-ambience-audition-${s.name}'),
              onTap: () => _audition(context, s),
              customBorder: const CircleBorder(),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(
                  isPlaying
                      ? Icons.stop_circle_outlined
                      : Icons.play_circle_outline,
                  size: 22,
                  color: isPlaying
                      ? AppColors.formAccentOf(context)
                      : AppColors.textSecondary(context),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    s.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.textPrimary(context),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    '${(s.bytes / (1024 * 1024)).toStringAsFixed(1)} MB'
                    ' · ${_ago(s.modifiedMs)}',
                    style: TextStyle(
                      color: AppColors.textTertiary(context),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected) ...[
              const SizedBox(width: 8),
              Icon(
                Icons.check_circle,
                size: 18,
                color: AppColors.formAccentOf(context),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _importFromFile(BuildContext context) async {
    final storage = Provider.of<StorageService>(context, listen: false);
    final result = await pickCustomAmbience(context, storage);
    if (!context.mounted) return;
    if (result.name != null) {
      await _load();
      if (context.mounted) widget.onPicked(result.name!);
      if (result.note != null && context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(result.note!)));
      }
      return;
    }
    if (result.error != null && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(result.error!)));
    }
  }

  static String _ago(int modifiedMs) {
    final age = DateTime.now().difference(
      DateTime.fromMillisecondsSinceEpoch(modifiedMs),
    );
    if (age.inDays <= 0) return 'today';
    if (age.inDays == 1) return 'yesterday';
    return '${age.inDays} days ago';
  }
}
