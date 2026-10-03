// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

part of 'expression_pack_dialog.dart';

extension _ExpressionPackDialogView on ExpressionPackDialogState {
  Widget _buildPack(BuildContext context) {
    final session = _session;
    final content = Column(
      children: [
        if (!widget.embedded) _header(context),
        Expanded(
          child: _checkingWorkflow
              ? const Center(child: CircularProgressIndicator())
              : session == null
              ? SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: ExpressionPackSetup(
                    busy: context.watch<ImageGenService>().isGenerating,
                    baseImage: widget.baseImage,
                    characterName: widget.characterName,
                    existingEmotions: widget.existingEmotions,
                    note: widget.note,
                    storage: widget.storage,
                    onCancel: widget.embedded
                        ? () => widget.onDiscard?.call()
                        : () => Navigator.of(context).pop(false),
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
    if (widget.embedded) return content;
    return ChangeNotifierProvider<StorageService>.value(
      value: widget.storage,
      child: Dialog(
        backgroundColor: AppColors.surfaceOf(context),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 720,
            maxHeight: MediaQuery.of(context).size.height * 0.94,
          ),
          child: content,
        ),
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
          Icon(Icons.theater_comedy, color: AppColors.formMasterAccent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Expression pack — ${widget.characterName}',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary(context),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: Icon(Icons.close, color: AppColors.iconSecondary(context)),
            onPressed: _close,
          ),
        ],
      ),
    );
  }
}
