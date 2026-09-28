// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/image/studio_desk_logic.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// The Comfy file the desk will actually run. Not a leftover checkpoint name.
class AvatarStudioLine extends StatelessWidget {
  const AvatarStudioLine({super.key, this.edit = false});

  final bool edit;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<StorageService>().imageGenSettings;
    final file = deskPrimaryFile(
      backend: settings.imageGenBackend,
      edit: edit,
      workflowId: edit
          ? settings.comfyEditWorkflowId
          : settings.comfyCreateWorkflowId,
      choices: edit
          ? settings.comfyEditModelChoices
          : settings.comfyCreateModelChoices,
      legacyModel: edit ? settings.imageGenEditModel : settings.imageGenModel,
    );
    final shown = file.isEmpty ? 'Choose a model on the desk' : file;
    return Text(
      edit ? 'Edit model: $shown' : 'Create model: $shown',
      style: TextStyle(color: AppColors.textSecondary(context), fontSize: 12),
    );
  }
}
