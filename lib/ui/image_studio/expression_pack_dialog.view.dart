// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

part of 'expression_pack_dialog.dart';

extension _ExpressionPackDialogView on ExpressionPackDialogState {
  Widget _buildPack(BuildContext context) {
    final session = _session;
    final content = Column(
      children: [
        Expanded(
          child: _checkingWorkflow
              ? const Center(child: CircularProgressIndicator())
              : session == null
              ? SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: ExpressionPackSetup(
                    busy:
                        widget.preparingPrompt ||
                        context.watch<ImageGenService>().isGenerating,
                    promptRules: _promptRules,
                    onRulesChanged: (rules) => _promptRules = rules,
                    originalPrompts: {
                      for (final emotion in kFullExpressionSet)
                        emotion: originalExpressionPrompt(
                          emotion: emotion,
                          basePrompt:
                              '${widget.basePrompt}, $kExpressionFraming',
                          editMode:
                              ImageGenBackend.fromKey(
                                    widget
                                        .storage
                                        .imageGenSettings
                                        .imageGenBackend,
                                  ) ==
                                  ImageGenBackend.comfyUi ||
                              ImageReferenceResolver.packEditMode(
                                widget.storage.imageGenSettings,
                              ),
                        ),
                    },
                    baseImage: widget.baseImage,
                    characterName: widget.characterName,
                    existingEmotions: widget.existingEmotions,
                    note: widget.note,
                    storage: widget.storage,
                    onCancel: () => widget.onDiscard?.call(),
                    onStart: _start,
                  ),
                )
              : ExpressionPackGrid(
                  storage: widget.storage,
                  session: session,
                  imageGen: widget.imageGen,
                  cancelRequested: _cancelRequested,
                  importing: _importing,
                  imported: _imported,
                  qc: _qc,
                  resolvingVision: _resolvingVision,
                  onVisionCheck: _runVisionCheck,
                  onCancel: () {
                    _setDialogState(() => _cancelRequested = true);
                    session.cancel();
                  },
                  onResume: () => unawaited(_resume(session)),
                  onImport: _import,
                ),
        ),
      ],
    );
    return content;
  }
}
