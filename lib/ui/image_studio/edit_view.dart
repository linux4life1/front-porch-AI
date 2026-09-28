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
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/image/edit_profile.dart';
import 'package:front_porch_ai/services/capability/capability.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/utils/utils.dart';

import 'edit_source_well.dart';
import 'result_view.dart';
import 'studio_desk_copy.dart';
import 'studio_desk_frame.dart';
import 'studio_edit_pane.dart';

/// The **Edit** tab: keep this exact character, describe the change. Feeds the
/// same [ImageGenService.generateImage] with `intent: StudioIntent.edit`, so the
/// reference is read as conditioning (identity pinned) — no denoise slider.
/// Self-contained (own source/instruction/result state) and reuses [ResultView];
/// [ImageReferenceResolver] drives whether editing is available at all.
class EditView extends StatefulWidget {
  /// Send the edited image to the launching conversation, when there is one.
  final Future<void> Function(Uint8List bytes, String text)? onSendToChat;

  /// Set the edited image as the avatar (crop → save), when the launch context
  /// supports it. Null hides the Accept action.
  final Future<void> Function(Uint8List bytes)? onAcceptBytes;

  /// Save the edit result to the character's Avatar Gallery (a look). Null when
  /// there's no character context.
  final Future<void> Function(Uint8List bytes)? onSaveToGalleryBytes;

  /// Label for the Accept action (e.g. "Set as portrait").
  final String acceptLabel;

  /// The character's current portrait path — pre-loaded as the source to edit so
  /// "Edit → change this portrait" starts from the existing avatar instead of an
  /// empty "Add photo". Null (persona / group shot) → the user picks a photo.
  final String? initialSourcePath;

  const EditView({
    super.key,
    this.onSendToChat,
    this.onAcceptBytes,
    this.onSaveToGalleryBytes,
    this.acceptLabel = 'Use image',
    this.initialSourcePath,
  });

  @override
  State<EditView> createState() => _EditViewState();
}

class _EditViewState extends State<EditView> {
  final TextEditingController _instructionCtrl = TextEditingController();
  Uint8List? _sourceBytes;
  Uint8List? _resultBytes;
  bool _busy = false;
  bool _saving = false;
  String _error = '';

  /// How strongly the instruction changes the reference (higher = more change).
  /// Defaults to "do what I asked" — multi-change instruction edits come out
  /// under-driven below full strength — and the user dials DOWN for subtle,
  /// identity-preserving edits. See [kEditRecommendedStrength].
  double _strength = kEditRecommendedStrength;

  @override
  void initState() {
    super.initState();
    _seedInitialSource();
  }

  @override
  void dispose() {
    _instructionCtrl.dispose();
    super.dispose();
  }

  /// Pre-load the character's current portrait as the source to edit, so the
  /// Edit tab opens ready to "change this portrait" rather than empty.
  Future<void> _seedInitialSource() async {
    final path = widget.initialSourcePath;
    if (path == null || path.isEmpty) return;
    try {
      final storage = Provider.of<StorageService>(context, listen: false);
      final file = storage.resolveCharacterImage(path);
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        if (mounted && _sourceBytes == null) {
          setState(() => _sourceBytes = bytes);
        }
      }
    } catch (_) {
      // Missing/unreadable portrait → the user can still add a photo manually.
    }
  }

  Future<void> _pickSource() async {
    final result = await PickerPrefs.pickFiles(
      category: PickerPrefs.catImage,
      dialogTitle: 'Select a photo to edit',
      type: FileType.image,
    );
    final bytes = await result?.firstBytes();
    if (bytes != null && mounted) setState(() => _sourceBytes = bytes);
  }

  Future<void> _generate() async {
    final instruction = _instructionCtrl.text.trim();
    if (_sourceBytes == null || instruction.isEmpty) return;
    setState(() {
      _busy = true;
      _error = '';
      _resultBytes = null;
    });
    final service = Provider.of<ImageGenService>(context, listen: false);
    try {
      final bytes = await service.generateImage(
        prompt: instruction,
        referenceImage: _sourceBytes,
        intent: StudioIntent.edit,
        editStrength: _strength,
      );
      if (!mounted) return;
      setState(() {
        _busy = false;
        _resultBytes = bytes;
        if (bytes == null) {
          _error = service.statusMessage.isNotEmpty
              ? service.statusMessage
              : 'The edit returned no image.';
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
        });
      }
    }
  }

  Future<void> _saveResult() async {
    final bytes = _resultBytes;
    if (bytes == null) return;
    setState(() => _saving = true);
    final service = Provider.of<ImageGenService>(context, listen: false);
    final path = await service.saveImageToDisk(bytes);
    if (!mounted) return;
    setState(() => _saving = false);
    if (path != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Image saved to $path'),
          backgroundColor: AppColors.resolve(
            context,
            AppColors.logReady,
            AppColors.lightBorder,
          ),
        ),
      );
    }
  }

  Future<void> _send() async {
    final bytes = _resultBytes;
    if (bytes == null || widget.onSendToChat == null) return;
    await widget.onSendToChat!(bytes, _instructionCtrl.text.trim());
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Image sent to chat')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final backendKey = context.select<StorageService, String>(
      (s) => s.imageGenSettings.imageGenBackend,
    );
    // Edit tab reads the EDIT slot (phase #12 model-slot split) — the create
    // slot's model is irrelevant here and used to poison/be poisoned by it.
    final model = context.select<StorageService, String>(
      (s) => s.imageGenSettings.imageGenEditModel,
    );
    final backend = ImageGenBackend.fromKey(backendKey);
    final cap = ImageReferenceResolver.resolveForBackend(
      backend: backend,
      modelName: model,
    );
    // Lock off the SHARED service so an edit and a Create generation can never
    // run at once (the studio also disables the Create tab while this is true).
    final genBusy = context.select<ImageGenService, bool>(
      (s) => s.isGenerating,
    );

    if (_resultBytes != null && _error.isEmpty) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: ResultView(
          imageBytes: _resultBytes!,
          hasAccept: widget.onAcceptBytes != null,
          acceptLabel: widget.acceptLabel,
          isSaving: _saving,
          onSave: _saveResult,
          onAccept: () {
            final cb = widget.onAcceptBytes;
            final bytes = _resultBytes;
            if (cb == null || bytes == null) return;
            setState(() => _saving = true);
            cb(bytes).whenComplete(() {
              if (mounted) setState(() => _saving = false);
            });
          },
          onVariations: (_busy || genBusy) ? () {} : _generate,
          onEditRegen: () => setState(() {
            _resultBytes = null;
            _error = '';
          }),
          onSendToChat: widget.onSendToChat == null ? null : _send,
          onSaveToGallery: widget.onSaveToGalleryBytes == null
              ? null
              : () {
                  final cb = widget.onSaveToGalleryBytes;
                  final bytes = _resultBytes;
                  if (cb == null || bytes == null) return;
                  setState(() => _saving = true);
                  cb(bytes).whenComplete(() {
                    if (mounted) setState(() => _saving = false);
                  });
                },
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: StudioDeskFrame(
        promptController: _instructionCtrl,
        well: kStudioEditWell,
        packNote: kStudioEditPack,
        picture: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!cap.supportsEdit)
              _degradeBanner(
                context,
                cap.degradeReason ??
                    'Editing isn’t available for the current image model.',
              ),
            EditSourceWell(
              bytes: _sourceBytes,
              busy: _busy,
              onPick: _pickSource,
              onClear: () => setState(() => _sourceBytes = null),
            ),
          ],
        ),
        stove: StudioEditPane(
          busy: _busy || genBusy,
          errorText: _error,
          onGenerate: (_busy || genBusy) ? null : _generate,
        ),
      ),
    );
  }

  Widget _degradeBanner(BuildContext context, String reason) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerOf(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline,
            size: 18,
            color: AppColors.iconSecondary(context),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              reason,
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: AppColors.textSecondary(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
