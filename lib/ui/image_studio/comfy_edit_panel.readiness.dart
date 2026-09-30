// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

part of 'comfy_edit_panel.dart';

extension _ComfyEditReadiness on _ComfyEditPanelState {
  (IconData, Color, String) _readinessState(
    StorageService st,
    ComfyEditPreset? preset,
    bool isUpload,
  ) {
    if (isUpload) {
      return this._computeReady(st)
          ? (
              Icons.check_circle,
              AppColors.logReady,
              'Ready — your workflow is loaded.',
            )
          : (
              Icons.warning_amber_rounded,
              AppColors.logWarn,
              'Upload a workflow with %IMAGE% and %PROMPT% to continue.',
            );
    }
    if (_loading && _missingNodes == null) {
      return (
        Icons.hourglass_empty,
        AppColors.textTertiary(context),
        'Checking your ComfyUI…',
      );
    }
    if (_slotsWorkflowId == st.imageGenSettings.comfyEditWorkflowId &&
        !_hasEditInputs) {
      return (
        Icons.warning_amber_rounded,
        AppColors.logWarn,
        'This workflow needs an image input and a prompt input for Edit.',
      );
    }
    if (_missingNodes == null) {
      return (
        Icons.error_outline,
        AppColors.logWarn,
        'Can’t reach ComfyUI. Make sure it’s running at the configured URL.',
      );
    }
    if (_missingNodes!.isNotEmpty) {
      return (
        Icons.warning_amber_rounded,
        AppColors.logWarn,
        'Your ComfyUI is missing: ${_missingNodes!.join(', ')}. Update ComfyUI '
            '(or its custom nodes), then reopen this.',
      );
    }
    final workflowId = st.imageGenSettings.comfyEditWorkflowId;
    for (final slot in _activeSlots) {
      final chosen =
          st.imageGenSettings.comfyEditModelChoice(workflowId, slot.token) ??
          '';
      if (!(_modelOptions['${slot.loaderClass}/${slot.inputName}'] ??
              const <String>[])
          .contains(chosen)) {
        return (
          Icons.warning_amber_rounded,
          AppColors.logWarn,
          'Pick a model for each slot above.',
        );
      }
    }
    return (Icons.check_circle, AppColors.logReady, 'Ready.');
  }
}
