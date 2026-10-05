// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';

import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/warm_dialog.dart';

import 'kcpps_editor_style.dart';

/// A yes-or-no question before something that cannot be undone.
Future<bool> askKcpps(
  BuildContext context, {
  required String title,
  required String text,
  required String yes,
  String no = 'Cancel',
  bool destructive = false,
}) async {
  final answer = await showWarmDialog<bool>(
    context,
    title: title,
    destructive: destructive,
    accent: AppColors.porchAmberOf(context),
    width: 420,
    content: Text(text, style: keText(context, size: 14, height: 1.45)),
    actions: [
      KeButton(no, onPressed: () => Navigator.of(context).pop(false)),
      KeButton(
        yes,
        kind: KeButtonKind.amber,
        onPressed: () => Navigator.of(context).pop(true),
      ),
    ],
  );
  return answer ?? false;
}

Future<bool> askDiscardKcpps(BuildContext context, String name) => askKcpps(
  context,
  title: 'Discard your changes?',
  text: 'The changes to "$name" have not been saved.',
  yes: 'Discard',
  no: 'Keep editing',
);

Future<bool> askReplaceKcpps(BuildContext context, String name) => askKcpps(
  context,
  title: 'Replace "$name"?',
  text: 'A preset called "$name" already exists. Saving replaces it.',
  yes: 'Replace',
);

/// Asked once before a placement edit replaces a preset's own MoE setting.
Future<bool> askReplaceOwnMoeKcpps(BuildContext context) => askKcpps(
  context,
  title: "Replace this preset's MoE setting?",
  text:
      'This preset keeps some of the model\'s experts in system memory with '
      'a MoE (experts on CPU) setting of its own. Changing how the model is '
      'placed replaces that setting with the placement chosen here.',
  yes: 'Replace and save',
);

Future<bool> askDeleteKcpps(
  BuildContext context,
  String name, {
  required bool inUse,
}) => askKcpps(
  context,
  title: 'Delete "$name"?',
  text: inUse
      ? 'Chat uses this preset. After deleting it, chat goes back to the '
            "app's own settings."
      : 'The preset file is deleted.',
  yes: 'Delete',
  destructive: true,
);
