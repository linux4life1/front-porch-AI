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
import 'package:front_porch_ai/services/capability/capability.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

import 'studio_widgets.dart';

/// Presentational shell for the Image Studio: the dialog frame, header, subject
/// picker, style/reference/prompt canvas, generate/result/history, and the
/// collapsible settings panel. All state + handlers live in the `ImageStudio`
/// coordinator; this widget is pure layout driven by the passed values and
/// callbacks (extracted to keep the coordinator under the 500-line cap).
class StudioView extends StatelessWidget {
  const StudioView({
    super.key,
    required this.activeMode,
    required this.characterName,
    this.groupCharacters = const [],
    this.groupShotActive = false,
    this.onPickGroupMember,
    this.onPickGroupShot,
    required this.prompt,
    required this.referenceBytes,
    required this.currentImageBytes,
    required this.error,
    this.generating = false,
    this.crafting = false,
    required this.saving,
    required this.isBusy,
    required this.history,
    required this.onClose,
    required this.onSelectSubject,
    required this.onPickReference,
    required this.onClearReference,
    required this.onPromptChanged,
    required this.onCraftLlm,
    this.onExpressionPack,
    required this.onGenerate,
    required this.onSave,
    required this.onAccept,
    required this.onVariations,
    required this.onEditRegen,
    required this.onSendToChat,
    this.onSaveToGallery,
    required this.onRestore,
    this.modeTabs,
    this.editBody,
    this.showEdit = false,
    this.workspaceIndex,
    this.expressionBody,
    this.draftBusy = false,
  });

  final ImageGenMode activeMode;
  final String? characterName;
  final List<({String name, String description, String? dbId})> groupCharacters;
  final bool groupShotActive;
  final ValueChanged<int>? onPickGroupMember;
  final VoidCallback? onPickGroupShot;
  final String prompt;
  final Uint8List? referenceBytes;
  final Uint8List? currentImageBytes;
  final String error;
  final bool generating;

  /// "Write it for me" is running.
  final bool crafting;
  final bool saving;
  final bool isBusy;
  final List<({String prompt, Uint8List bytes, String style})> history;

  final VoidCallback onClose;
  final ValueChanged<ImageGenMode> onSelectSubject;
  final VoidCallback onPickReference;
  final VoidCallback onClearReference;
  final ValueChanged<String> onPromptChanged;

  /// The LLM prompt writer behind "Write it for me".
  final VoidCallback onCraftLlm;

  /// Non-null only when the active subject can take an Expression pack (a
  /// character portrait with a library home — never group shot or persona).
  final VoidCallback? onExpressionPack;
  final VoidCallback onGenerate;
  final VoidCallback onSave;
  final VoidCallback onAccept;
  final VoidCallback onVariations;
  final VoidCallback onEditRegen;
  final VoidCallback? onSendToChat;
  final VoidCallback? onSaveToGallery;
  final ValueChanged<({String prompt, Uint8List bytes, String style})>
  onRestore;

  /// The Create | Edit tab bar, rendered under the header (null = no tabs).
  final Widget? modeTabs;

  /// The Edit tab's body, kept alive alongside Create via an IndexedStack.
  final Widget? editBody;

  /// True when the Edit tab is active.
  final bool showEdit;
  final int? workspaceIndex;
  final Widget? expressionBody;
  final bool draftBusy;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surfaceOf(context),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 1040,
          maxHeight: MediaQuery.of(context).size.height * 0.94,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _header(context),
            ?modeTabs,
            Flexible(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final desk = _desk(context);
                  final wide = constraints.maxWidth >= 700;
                  final create = wide
                      ? Padding(padding: const EdgeInsets.all(20), child: desk)
                      : SingleChildScrollView(
                          padding: const EdgeInsets.all(20),
                          child: desk,
                        );
                  return IndexedStack(
                    sizing: StackFit.expand,
                    index: workspaceIndex ?? (showEdit ? 1 : 0),
                    children: [
                      ExcludeFocus(
                        excluding: (workspaceIndex ?? (showEdit ? 1 : 0)) != 0,
                        child: create,
                      ),
                      ExcludeFocus(
                        excluding: (workspaceIndex ?? (showEdit ? 1 : 0)) != 1,
                        child: editBody ?? const SizedBox.shrink(),
                      ),
                      if (expressionBody != null)
                        ExcludeFocus(
                          excluding: workspaceIndex != 2,
                          child: expressionBody!,
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _desk(BuildContext context) {
    return StudioDeskFrame(
      subject: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SubjectPicker(
            selected: activeMode,
            characterName: characterName,
            groupCharacters: groupCharacters,
            onChanged: draftBusy ? null : onSelectSubject,
            onPickGroupMember: draftBusy ? null : onPickGroupMember,
            onPickGroupShot: draftBusy ? null : onPickGroupShot,
          ),
          if (groupShotActive) ...[
            const SizedBox(height: 8),
            _groupShotCaveat(context),
          ],
        ],
      ),
      prompt: prompt,
      onPromptChanged: draftBusy ? null : onPromptChanged,
      onCraft: draftBusy ? null : onCraftLlm,
      crafting: crafting,
      well: kStudioCreateWell,
      packNote:
          context.watch<StorageService>().imageGenSettings.imageGenBackend ==
                  'comfyui' ||
              ImageReferenceResolver.packEditMode(
                context.watch<StorageService>().imageGenSettings,
              )
          ? 'Pack uses the Edit model and workflow.'
          : kStudioCreatePack,
      showPack: onExpressionPack != null,
      onExpressionPack: onExpressionPack,
      picture: ReferenceImagePicker(
        referenceBytes: referenceBytes,
        isBusy: draftBusy,
        onPick: onPickReference,
        onClear: onClearReference,
      ),
      output: _result(context),
      stove: StudioDesk(
        editMode: false,
        showGenerate: true,
        onGenerate: isBusy ? null : onGenerate,
        errorText: error,
        generating: generating,
      ),
    );
  }

  Widget? _result(BuildContext context) {
    final showImage = currentImageBytes != null && error.isEmpty;
    if (!showImage && history.isEmpty) return null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: showImage
              ? ResultView(
                  key: const ValueKey('result'),
                  imageBytes: currentImageBytes!,
                  hasAccept: hasAcceptAction(activeMode),
                  acceptLabel: getAcceptLabel(activeMode),
                  isSaving: saving,
                  onSave: onSave,
                  onAccept: onAccept,
                  onVariations: isBusy ? null : onVariations,
                  onEditRegen: onEditRegen,
                  onSendToChat: onSendToChat,
                  onSaveToGallery: onSaveToGallery,
                )
              : const SizedBox.shrink(),
        ),
        if (history.isNotEmpty) ...[
          const SizedBox(height: 16),
          GenerationHistory(entries: history, onRestore: onRestore),
        ],
      ],
    );
  }

  /// Honest warning shown while the whole-cast "Group shot" subject is active.
  Widget _groupShotCaveat(BuildContext context) {
    final warn = AppColors.resolve(
      context,
      const Color(0xFFDAA83F),
      const Color(0xFFA97514),
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: warn.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: warn.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, size: 15, color: warn),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Group shot: rendering multiple specific characters in one image is '
              'unreliable — faces and features often blend or mix up. Results vary '
              'a lot by model; expect a few re-rolls.',
              style: TextStyle(
                color: AppColors.textSecondary(context),
                fontSize: 11.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.borderOf(context))),
      ),
      child: Row(
        children: [
          Icon(Icons.auto_awesome, color: AppColors.formMasterAccent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Image Studio',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary(context),
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.close, color: AppColors.iconSecondary(context)),
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}
