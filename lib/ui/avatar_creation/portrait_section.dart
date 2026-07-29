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

import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:front_porch_ai/ui/dialogs/avatar_gallery/avatar_gallery_io.dart';
import 'package:front_porch_ai/ui/dialogs/image_crop_dialog.dart';
import 'package:front_porch_ai/ui/dialogs/image_gen_settings_dialog.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

import 'avatar_creation_controller.dart';
import 'engine_strip.dart';
import 'upload_tag_dialog.dart';

/// "Portrait — pick a source": the upload/generate/none segments, the upload
/// wells (count follows the pack toggle — ONE when the pack is on, since that
/// image is its identity base; multi with emotion tagging when off), and the
/// generate flow's engine strip + prompt. Portrait source and expression
/// generation are deliberately INDEPENDENT sections (locked decision k).
class PortraitSection extends StatelessWidget {
  const PortraitSection({super.key, required this.controller});

  final AvatarCreationController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'PORTRAIT — PICK A SOURCE',
          style: TextStyle(
            fontSize: 10.5,
            letterSpacing: 0.8,
            fontWeight: FontWeight.w700,
            color: AppColors.textTertiary(context),
          ),
        ),
        const SizedBox(height: 8),
        _modes(context, c),
        if (!c.engineReady) ...[const SizedBox(height: 10), _noEngine(context, c)],
        if (c.source == PortraitSource.generate && c.engineReady) ...[
          const SizedBox(height: 12),
          EngineStrip(controller: c),
          const SizedBox(height: 12),
          _promptField(context, c),
          // The compact "saved as card image" preview — hidden during the
          // review pause, where the large zoomable preview in the review card
          // shows the same portrait (avoids the same image in two spots).
          if (c.portraitBytes != null &&
              c.stage != AvatarRunStage.portraitReview) ...[
            const SizedBox(height: 10),
            _portraitPreview(context, c),
          ],
        ],
        if (c.source == PortraitSource.upload) ...[
          const SizedBox(height: 12),
          _uploadWells(context, c),
        ],
        if (c.source == PortraitSource.none) ...[
          const SizedBox(height: 10),
          Text(
            'No portrait for now — later, open Avatar Gallery and use '
            'Set portrait (or Add avatar + ★) on the home screen.',
            style: TextStyle(
              color: AppColors.textTertiary(context),
              fontSize: 11.5,
            ),
          ),
        ],
      ],
    );
  }

  Widget _modes(BuildContext context, AvatarCreationController c) {
    Widget mode(PortraitSource s, IconData icon, String label, {bool enabled = true}) {
      final selected = c.source == s;
      final accent = AppColors.formMasterAccent;
      return Expanded(
        child: GestureDetector(
          onTap: (enabled && !c.running) ? () => c.setSource(s) : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(
              color: selected
                  ? accent.withValues(alpha: 0.10)
                  : AppColors.surfaceContainerOf(context),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(
                color: selected ? accent : AppColors.borderOf(context),
              ),
            ),
            // FittedBox(scaleDown) so the icon + label shrink a hair instead of
            // overflowing when the three equal-width buttons get narrow (the
            // longest label, "Upload my own", overran its third by ~6px on
            // smaller windows). scaleDown never enlarges, so at normal widths
            // this is a no-op; when cramped it scales down imperceptibly with no
            // text clipping — robust across the three platforms' font metrics.
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    icon,
                    size: 15,
                    color: !enabled
                        ? AppColors.textTertiary(context)
                        : selected
                        ? accent
                        : AppColors.iconSecondary(context),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                      color: !enabled
                          ? AppColors.textTertiary(context)
                          : selected
                          ? accent
                          : AppColors.textSecondary(context),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        mode(PortraitSource.upload, Icons.upload_outlined, 'Upload my own'),
        mode(
          PortraitSource.generate,
          Icons.auto_awesome,
          'Generate',
          enabled: c.engineReady,
        ),
        mode(PortraitSource.none, Icons.hourglass_empty, 'None for now'),
      ],
    );
  }

  Widget _noEngine(BuildContext context, AvatarCreationController c) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: AppColors.formMasterAccent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
          color: AppColors.formMasterAccent.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Generate is unavailable — no image engine is set up. Configure '
              'one, or upload images instead.',
              style: TextStyle(
                color: AppColors.textSecondary(context),
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ),
          TextButton(
            onPressed: () async {
              await showDialog(
                context: context,
                builder: (_) => const ImageGenSettingsDialog(),
              );
              c.refreshEngine();
            },
            style: TextButton.styleFrom(
              foregroundColor: AppColors.formMasterAccent,
            ),
            child: const Text('Set up', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _promptField(BuildContext context, AvatarCreationController c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'PORTRAIT PROMPT',
              style: TextStyle(
                fontSize: 10.5,
                letterSpacing: 0.8,
                fontWeight: FontWeight.w700,
                color: AppColors.textTertiary(context),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'seeded from your description — edit freely',
              style: TextStyle(
                fontSize: 11,
                color: AppColors.textTertiary(context),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        TextField(
          controller: c.promptController,
          enabled: c.promptEditable,
          maxLines: 3,
          minLines: 2,
          style: TextStyle(color: AppColors.textPrimary(context), fontSize: 13),
          decoration: InputDecoration(
            hintText: 'Describe the character portrait…',
            hintStyle: TextStyle(color: AppColors.textTertiary(context)),
            filled: true,
            fillColor: AppColors.surfaceContainerOf(context),
            contentPadding: const EdgeInsets.all(12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: AppColors.borderOf(context)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: AppColors.borderOf(context)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColors.formMasterAccent),
            ),
          ),
        ),
      ],
    );
  }

  Widget _portraitPreview(BuildContext context, AvatarCreationController c) {
    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.memory(
            c.portraitBytes!,
            width: 64,
            height: 80,
            fit: BoxFit.cover,
          ),
        ),
        const SizedBox(width: 10),
        Text(
          'Saved & set as the card image.',
          style: TextStyle(
            color: AppColors.textSecondary(context),
            fontSize: 11.5,
          ),
        ),
      ],
    );
  }

  // ── Upload wells ──────────────────────────────────────────────────────────
  Widget _uploadWells(BuildContext context, AvatarCreationController c) {
    final packOn = c.packEnabled && c.packPossible;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _well(
              context,
              bytes: c.portraitBytes,
              caption: 'portrait',
              onTap: c.running ? null : () => _pickPortrait(context, c),
            ),
            if (!packOn) ...[
              for (final u in c.extraUploads)
                _well(
                  context,
                  bytes: u.bytes,
                  caption: u.emotion ?? 'look',
                ),
              _well(
                context,
                bytes: null,
                caption: '＋',
                onTap: c.running ? null : () => _pickExtra(context, c),
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        Text(
          packOn
              ? 'Exactly one image — it becomes the portrait AND the '
                    'expression pack\'s identity base.'
              : 'First image is the portrait; add more as gallery looks, or '
                    'tag one with an emotion to make it an expression image.',
          style: TextStyle(
            color: AppColors.textTertiary(context),
            fontSize: 11,
            height: 1.35,
          ),
        ),
      ],
    );
  }

  Widget _well(
    BuildContext context, {
    required Uint8List? bytes,
    required String caption,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 64,
        height: 80,
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerOf(context),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: bytes != null
                ? AppColors.borderOf(context)
                : AppColors.textTertiary(context),
          ),
          image: bytes != null
              ? DecorationImage(image: MemoryImage(bytes), fit: BoxFit.cover)
              : null,
        ),
        child: bytes == null
            ? Center(
                child: Text(
                  caption == '＋' ? '＋' : '⬆',
                  style: TextStyle(
                    fontSize: 18,
                    color: AppColors.textTertiary(context),
                  ),
                ),
              )
            : Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  width: double.infinity,
                  color: AppColors.backgroundOf(context).withValues(alpha: 0.65),
                  padding: const EdgeInsets.symmetric(vertical: 1),
                  child: Text(
                    caption,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 9,
                      color: AppColors.textSecondary(context),
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  Future<void> _pickPortrait(BuildContext context, AvatarCreationController c) async {
    final bytes = await pickImageBytes();
    if (bytes == null || !context.mounted) return;
    // Same crop step the gallery's "Replace portrait" uses.
    final cropped = await ImageCropDialog.show(context, imageBytes: bytes);
    if (cropped == null) return;
    final ok = await c.applyPortrait(cropped);
    if (!ok && context.mounted) _saveFailed(context);
  }

  Future<void> _pickExtra(BuildContext context, AvatarCreationController c) async {
    final bytes = await pickImageBytes();
    if (bytes == null || !context.mounted) return;
    final choice = await showUploadTagDialog(context, bytes);
    if (choice == null || !context.mounted) return;
    final ok = await c.addExtraUpload(
      bytes,
      choice == kUploadTagLook ? null : choice,
    );
    if (!ok && context.mounted) _saveFailed(context);
  }

  void _saveFailed(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('The character could not be saved — image not added.'),
      ),
    );
  }
}
