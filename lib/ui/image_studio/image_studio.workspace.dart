// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

part of 'image_studio.dart';

extension _ImageStudioWorkspace on _ImageStudioState {
  Future<void> _closeStudio() async {
    if (!await (_expressionsKey.currentState?.confirmClose() ??
            Future.value(true)) ||
        !mounted) {
      return;
    }
    rebuildState(() => _allowClose = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.pop(context);
    });
  }

  Widget _buildStudio(BuildContext context) {
    _dropStaleError();
    // Any generation (Create OR Edit) flips the shared service busy; fold it in
    // so Create cannot submit while another workspace is generating.
    final genBusy = context.select<ImageGenService, bool>(
      (s) => s.isGenerating,
    );

    return PopScope(
      canPop: _allowClose || !(_expressionsKey.currentState?.hasPack ?? false),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _closeStudio();
      },
      child: StudioView(
        activeMode: _activeMode,
        characterName: _activeCharName,
        groupCharacters: widget.groupCharacters,
        groupShotActive: _groupShot,
        onPickGroupMember: _pickGroupSubject,
        onPickGroupShot: () => _pickGroupSubject(null),
        prompt: _editablePrompt,
        referenceBytes: _referenceImageBytes,
        currentImageBytes: _currentImageBytes,
        error: _error,
        generating: _isGenerating,
        crafting: _isCrafting,
        saving: _saving,
        isBusy: _isBusy || genBusy,
        history: _history,
        onClose: _closeStudio,
        onSelectSubject: _selectSubject,
        onPickReference: _pickReferenceImage,
        onClearReference: () => rebuildState(() => _referenceImageBytes = null),
        onPromptChanged: _updatePrompt,
        onCraftLlm: _craftWithLlmIfAvailable,
        onExpressionPack: _packTargetDbId == null ? null : _openExpressionPack,
        onGenerate: _generate,
        onSave: _save,
        onAccept: _accept,
        onVariations: _variations,
        onEditRegen: _editAndRegen,
        onSendToChat: _sendToChat,
        onSaveToGallery: _canSaveToGallery ? _saveToGallery : null,
        onRestore: _restoreFromHistory,
        showEdit: _studioTab == 1,
        workspaceIndex: _studioTab,
        draftBusy: _isBusy,
        expressionBody: StudioExpressionTab(
          key: _expressionsKey,
          initialCharacterId: widget.characterDbId,
          groupCharacterIds: [
            for (final c in widget.groupCharacters)
              if (c.dbId != null) c.dbId!,
          ],
          lastStudioImage: _lastStudioImage,
          onImported: widget.onExpressionsImported,
          onPackChanged: () => rebuildState(() {}),
        ),
        modeTabs: StudioModeTabs(
          selected: _studioTab,
          onChanged: (i) => rebuildState(() => _studioTab = i),
          enabled: true,
        ),
        editBody: EditView(
          onResultImage: (bytes) =>
              rebuildState(() => _lastStudioImage = bytes),
          onSendToChat: widget.onSendToChat,
          onAcceptBytes: hasAcceptAction(_activeMode)
              ? (bytes) => _accept(bytes)
              : null,
          onSaveToGalleryBytes: _canSaveToGallery
              ? (bytes) => _saveToGallery(bytes)
              : null,
          acceptLabel: getAcceptLabel(_activeMode),
          // Pre-load the current portrait as the edit source (the user can still
          // swap in an unrelated photo via "Add photo").
          initialSourcePath: widget.characterImagePath,
        ),
      ),
    );
  }
}
