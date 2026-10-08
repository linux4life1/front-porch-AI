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

import 'package:flutter/material.dart';

import 'package:front_porch_ai/services/backend_manager.dart';
import 'package:front_porch_ai/services/kobold/kobold.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

/// The start-up box about the managed KoboldCpp. An engine below the floor
/// gets the red box: it cannot be put off, since every launch would refuse
/// the engine anyway, so the choices are the update or removing it (the app
/// downloads a current one again from Settings when asked). A newer release
/// gets the amber box with a "Not now" that holds a few days. The download
/// runs inside the box, through the same manager the Settings page uses.
class KoboldUpdateDialog extends StatefulWidget {
  const KoboldUpdateDialog({
    super.key,
    required this.manager,
    required this.gate,
  });

  final BackendManager manager;
  final KoboldUpdateGate gate;

  static Future<void> show(
    BuildContext context,
    BackendManager manager,
    KoboldUpdateGate gate,
  ) => showWarmDialogOf<void>(
    context,
    barrierDismissible: false,
    builder: (_) => KoboldUpdateDialog(manager: manager, gate: gate),
  );

  @override
  State<KoboldUpdateDialog> createState() => _KoboldUpdateDialogState();
}

enum _Phase { asking, downloading, done, failed, removeFailed }

class _KoboldUpdateDialogState extends State<KoboldUpdateDialog> {
  _Phase _phase = _Phase.asking;
  String _problem = '';

  bool get _tooOld => widget.gate == KoboldUpdateGate.tooOld;
  BackendManager get _manager => widget.manager;

  String get _have {
    final v = _manager.localVersion;
    return v == null ? 'your copy' : 'KoboldCpp $v';
  }

  Future<void> _update() async {
    setState(() => _phase = _Phase.downloading);
    await _manager.downloadBackend();
    if (!mounted) return;
    final error = _manager.error;
    setState(() {
      if (error == null) {
        _phase = _Phase.done;
      } else {
        _phase = _Phase.failed;
        _problem = error.replaceFirst(RegExp(r'^Error: (Exception: )?'), '');
      }
    });
  }

  Future<void> _notNow() async {
    final remote = _manager.remoteVersion;
    if (remote != null) await _manager.snoozeUpdate(remote);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _remove() async {
    final why = await _manager.removeEngine();
    if (!mounted) return;
    if (why == null) {
      Navigator.of(context).pop();
    } else {
      setState(() {
        _phase = _Phase.removeFailed;
        _problem = why;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = _phase == _Phase.downloading;
    return PopScope(
      // Esc and the back gesture are the same as the missing X: the red box
      // only leaves by one of its buttons, the amber one by "Not now".
      canPop: false,
      child: WarmDialog(
        title: _title,
        icon: _tooOld ? Icons.error_outline : Icons.system_update_alt,
        destructive: _tooOld,
        accent: _tooOld ? null : AppColors.porchAmberOf(context),
        width: 460,
        content: ListenableBuilder(
          listenable: _manager,
          builder: (context, _) => _body(context),
        ),
        actions: busy ? null : _actions(context),
      ),
    );
  }

  String get _title => switch (_phase) {
    _Phase.done => 'KoboldCpp is up to date',
    _Phase.downloading => 'Updating KoboldCpp',
    _ => _tooOld ? 'KoboldCpp is too old to run' : 'KoboldCpp has an update',
  };

  Widget _body(BuildContext context) {
    switch (_phase) {
      case _Phase.downloading:
        final progress = _manager.downloadProgress;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            WarmDialogText(_manager.statusMessage),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: progress > 0 && progress < 1 ? progress : null,
              color: AppColors.porchAmberOf(context),
              backgroundColor: AppColors.borderOf(context),
            ),
          ],
        );
      case _Phase.done:
        final v = _manager.localVersion;
        return WarmDialogText(
          v == null
              ? 'The new KoboldCpp is installed and ready.'
              : 'KoboldCpp $v is installed and ready.',
        );
      case _Phase.failed:
        return WarmDialogText(
          'The download did not finish: $_problem\n\n'
          'Check your connection and try again.',
        );
      case _Phase.removeFailed:
        return WarmDialogText('$_problem\n\nYou can try again.');
      case _Phase.asking:
        return WarmDialogText(_tooOld ? _tooOldWords : _newerWords);
    }
  }

  String get _tooOldWords =>
      'This version of Front Porch AI writes settings that KoboldCpp '
      '${KoboldBinaryVersion.minimum} and newer understand. You have $_have, '
      'so it cannot start until it is updated. Updating keeps your models '
      'and presets.\n\n'
      'If you use another backend and do not need KoboldCpp, remove it '
      'instead; the app can download it again from Settings → Backend at '
      'any time.';

  String get _newerWords {
    final remote = _manager.remoteVersion;
    return 'You have $_have; KoboldCpp $remote is out. Updating takes about '
        'a minute and keeps your models and presets.';
  }

  List<Widget> _actions(BuildContext context) {
    switch (_phase) {
      case _Phase.done:
        return [
          warmDialogConfirm(
            context,
            label: 'Done',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ];
      case _Phase.downloading:
        return const [];
      case _Phase.asking:
      case _Phase.failed:
      case _Phase.removeFailed:
        final retry = _phase != _Phase.asking;
        return [
          _secondary(
            context,
            _tooOld ? 'Remove it, I use something else' : 'Not now',
            _tooOld ? _remove : _notNow,
          ),
          warmDialogConfirm(
            context,
            label: retry ? 'Try again' : 'Update now',
            onPressed: _update,
          ),
        ];
    }
  }

  /// The quiet second choice, in the cancel button's colour; it does more
  /// than pop, which is why it is not [warmDialogCancel].
  Widget _secondary(BuildContext context, String label, VoidCallback onTap) =>
      TextButton(
        onPressed: onTap,
        child: Text(
          label,
          style: TextStyle(color: AppColors.textSecondary(context)),
        ),
      );
}
