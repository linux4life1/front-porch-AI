// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

part of 'expression_pack_dialog.dart';

extension _ExpressionPackDialogQc on _ExpressionPackDialogState {
  Future<void> _runVisionCheck() async {
    final session = _session;
    if (session == null || _resolvingVision || (_qc?.isRunning ?? false)) {
      return;
    }
    _setDialogState(() => _resolvingVision = true);
    final fire = await resolveVisionFireWithExplainer(context);
    if (!mounted) return;
    _setDialogState(() => _resolvingVision = false);
    if (fire == null) return;
    final previous = _qc;
    previous?.cancel();
    final qc = ExpressionPackQc(
      slots: session.slots,
      baseImageB64: _baseB64,
      fire: fire,
    );
    _setDialogState(() => _qc = qc);
    // Safe immediate disposal: the grid's ListenableBuilder unsubscribes from
    // the old controller during the rebuild, and ChangeNotifier explicitly
    // permits removeListener after dispose.
    previous?.dispose();
    unawaited(qc.run());
  }
}
