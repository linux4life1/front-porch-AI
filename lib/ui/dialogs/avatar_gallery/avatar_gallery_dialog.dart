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
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/services/character_repository.dart';
import 'package:front_porch_ai/services/chat_service.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/ui/dialogs/avatar_gallery/avatar_gallery_controller.dart';
import 'package:front_porch_ai/ui/dialogs/avatar_gallery/avatar_gallery_expressions_section.dart';
import 'package:front_porch_ai/ui/dialogs/avatar_gallery/avatar_gallery_looks_section.dart';
import 'package:front_porch_ai/ui/dialogs/avatar_gallery/avatar_gallery_io.dart';
import 'package:front_porch_ai/ui/dialogs/avatar_gallery/emotion_picker.dart';
import 'package:front_porch_ai/ui/dialogs/image_crop_dialog.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/warm_dialog.dart';

/// The one unified Avatar Gallery — gallery avatars + expression images in a
/// single warm-porch dialog, sharing one ★ canonical-avatar star. Replaces the
/// old glassmorphic `character_avatars_dialog.dart`.
///
/// [character] MUST be the origin LIBRARY card (the caller resolves group members
/// first). [mode] is caller-passed: [WardrobeMode.inChat] enables per-chat
/// selection and needs [chatService].
Future<void> showAvatarGallery({
  required BuildContext context,
  required CharacterCard character,
  required CharacterRepository repository,
  required StorageService storage,
  required WardrobeMode mode,
  ChatService? chatService,
}) {
  if (character.dbId == null) return Future.value();
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (_) => _AvatarGalleryDialog(
      controller: AvatarGalleryController(
        libraryCard: character,
        repository: repository,
        storage: storage,
        mode: mode,
        chat: chatService,
      ),
    ),
  );
}

class _AvatarGalleryDialog extends StatefulWidget {
  const _AvatarGalleryDialog({required this.controller});
  final AvatarGalleryController controller;

  @override
  State<_AvatarGalleryDialog> createState() => _AvatarGalleryDialogState();
}

class _AvatarGalleryDialogState extends State<_AvatarGalleryDialog> {
  AvatarGalleryController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    _c.addListener(_onChange);
    _c.init();
  }

  @override
  void dispose() {
    _c.removeListener(_onChange);
    _c.dispose();
    super.dispose();
  }

  void _onChange() {
    if (!mounted) return;
    final err = _c.lastError;
    if (err != null) {
      _c.lastError = null;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Something went wrong: $err')));
    }
    setState(() {});
  }

  // ── Add flows (pickers live here; the controller does the persistence) ──────
  Future<void> _addLook() async {
    final bytes = await pickImageBytes();
    if (bytes != null) await _c.addLook(bytes);
  }

  Future<void> _replacePortrait() async {
    final bytes = await pickImageBytes();
    if (bytes == null || !mounted) return;
    final cropped = await ImageCropDialog.show(context, imageBytes: bytes);
    if (cropped == null) return;
    final dir = _c.storage.charactersDir;
    await dir.create(recursive: true);
    final safe = _c.libraryCard.name
        .replaceAll(RegExp(r'[^\w\s\-]'), '')
        .replaceAll(' ', '_');
    final path =
        '${dir.path}/${safe}_${DateTime.now().millisecondsSinceEpoch}.png';
    await File(path).writeAsBytes(cropped);
    await _c.replacePortrait(path);
  }

  Future<void> _addExpression() async {
    final bytes = await pickImageBytes();
    if (bytes == null || !mounted) return;
    final emotion = await _pickEmotion(preview: bytes);
    if (emotion == null) return;
    await _c.addExpression(bytes, emotion);
  }

  Future<void> _relabel(String avatarId) async {
    final emotion = await _pickEmotion();
    if (emotion != null) _c.setLabelDraft(avatarId, emotion);
  }

  Future<void> _importZip() async {
    final zip = await pickZipBytes();
    if (zip == null) return;
    final pack = decodeSpritePack(zip);
    final (added, unrecognized, skipped) = await _c.importSpritePack(
      [for (final e in pack.entries) (bytes: e.bytes, emotion: e.emotion)],
      pack.unrecognized,
    );
    if (!mounted) return;
    final parts = <String>[
      'Imported $added',
      if (skipped > 0) '$skipped skipped (30 cap)',
      if (unrecognized > 0) '$unrecognized unrecognized',
    ];
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(parts.join(' · '))));
  }

  Future<String?> _pickEmotion({Uint8List? preview}) {
    return showDialog<String>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (dctx) => Dialog(
        backgroundColor: AppColors.surfaceOf(dctx),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460, maxHeight: 420),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: EmotionPicker(
              previewBytes: preview,
              onPick: (e) => Navigator.pop(dctx, e),
              onCancel: () => Navigator.pop(dctx),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(String avatarId) async {
    final img =
        _c.looks.where((l) => l.id == avatarId).firstOrNull ??
        _c.expressions.where((e) => e.id == avatarId).firstOrNull;
    if (img == null) return;
    final ok = await showWarmDialog<bool>(
      context,
      title: 'Delete this image?',
      content: const WarmDialogText(
        'This removes it from the gallery. It won\'t touch the portrait.',
      ),
      actions: [
        warmDialogCancel(context),
        warmDialogConfirm(
          context,
          label: 'Delete',
          destructive: true,
          onPressed: () => Navigator.pop(context, true),
        ),
      ],
    );
    if (ok == true) await _c.remove(img);
  }

  Future<void> _confirmDeletePortrait() async {
    final ok = await showWarmDialog<bool>(
      context,
      title: 'Delete the portrait?',
      content: const WarmDialogText(
        'A gallery avatar becomes the new portrait — the ★ one when a '
        'gallery avatar is starred, otherwise the first. The old portrait '
        'image is replaced.',
      ),
      actions: [
        warmDialogCancel(context),
        warmDialogConfirm(
          context,
          label: 'Delete portrait',
          destructive: true,
          onPressed: () => Navigator.pop(context, true),
        ),
      ],
    );
    if (ok == true) await _c.deletePortrait();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      backgroundColor: AppColors.surfaceOf(context),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 740),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _header(),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 4, 18, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AvatarGalleryLooksSection(
                      controller: _c,
                      onAddLook: _addLook,
                      onReplacePortrait: _replacePortrait,
                      onDelete: _confirmDelete,
                      onDeletePortrait: _confirmDeletePortrait,
                    ),
                    const SizedBox(height: 22),
                    Divider(
                      color: AppColors.borderOf(context).withValues(alpha: 0.4),
                    ),
                    const SizedBox(height: 14),
                    AvatarGalleryExpressionsSection(
                      controller: _c,
                      onAddExpression: _addExpression,
                      onImportZip: _importZip,
                      onExpand: () {
                        _c.expressionsExpanded = true;
                        _onChange();
                        _addExpression();
                      },
                      onRelabel: _relabel,
                      onDelete: _confirmDelete,
                    ),
                  ],
                ),
              ),
            ),
            _actionBar(),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 14, 14),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: AppColors.borderOf(context).withValues(alpha: 0.4),
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.photo_library_outlined, color: AppColors.formMasterAccent),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Avatar Gallery — ${_c.libraryCard.name}',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary(context),
              ),
            ),
          ),
          if (_c.saving)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              ),
            ),
          IconButton(
            tooltip: 'Close',
            icon: Icon(Icons.close, color: AppColors.iconSecondary(context)),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
    );
  }

  Widget _actionBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: AppColors.borderOf(context).withValues(alpha: 0.4),
          ),
        ),
      ),
      child: Row(
        children: [
          Flexible(
            child: Text(
              '${_c.looks.length} gallery · ${_c.expressions.length} expressions'
              '${_c.expressions.isEmpty ? '' : ' · emotion labels save on Done'}',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textTertiary(context),
              ),
            ),
          ),
          const SizedBox(width: 12),
          FilledButton(
            onPressed: _c.saving
                ? null
                : () async {
                    await _c.flushOnDone();
                    if (mounted) Navigator.of(context).pop();
                  },
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }
}
