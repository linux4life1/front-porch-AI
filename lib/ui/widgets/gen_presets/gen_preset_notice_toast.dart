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
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/gen_presets/gen_presets.dart';
import 'package:front_porch_ai/services/storage_service.dart';

import 'gen_preset_access.dart';

/// Shows each model-switch notice once, as a snack bar with Undo. Mounted
/// once in the desktop shell, so a switch from Settings, the chat's Model
/// Settings or the web app all land here. Renders nothing itself.
class GenPresetNoticeToast extends StatefulWidget {
  const GenPresetNoticeToast({super.key});

  @override
  State<GenPresetNoticeToast> createState() => _GenPresetNoticeToastState();
}

class _GenPresetNoticeToastState extends State<GenPresetNoticeToast> {
  GenPresetFollower? _follower;
  int? _lastShown;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final follower = genPresetsOf(
      Provider.of<StorageService>(context, listen: false),
    )?.follower;
    if (identical(follower, _follower)) return;
    _follower?.notice.removeListener(_onNotice);
    _follower = follower;
    follower?.notice.addListener(_onNotice);
  }

  @override
  void dispose() {
    _follower?.notice.removeListener(_onNotice);
    super.dispose();
  }

  void _onNotice() {
    final follower = _follower;
    final notice = follower?.notice.value;
    if (follower == null || notice == null || notice.id == _lastShown) return;
    _lastShown = notice.id;
    // Notices arrive from settings writes that may be mid-frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || follower.notice.value?.id != notice.id) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      if (messenger == null) return;
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          key: ValueKey('gen-preset-notice-${notice.id}'),
          content: Text(notice.message),
          duration: const Duration(seconds: 8),
          // Without persist:false, action snack bars never auto-dismiss.
          persist: false,
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => _undo(follower, notice.id),
          ),
        ),
      );
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> _undo(GenPresetFollower follower, int id) async {
    try {
      await follower.undo(id);
    } catch (error) {
      debugPrint('[GenPresets] undo failed: $error');
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('Could not undo the switch: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
