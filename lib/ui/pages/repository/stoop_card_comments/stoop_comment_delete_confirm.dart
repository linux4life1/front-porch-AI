// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

import 'package:flutter/material.dart';

import 'package:front_porch_ai/ui/pages/repository/stoop_glass.dart';

/// Asks before deleting a comment or reply. True only on an explicit Delete.
Future<bool> confirmStoopCommentDelete(
  BuildContext context, {
  required String title,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: stoopCard2(ctx),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: stoopBorderHi(ctx)),
      ),
      title: Text(title, style: stoopDisplay(ctx, size: 19)),
      content: Text(
        'The row stays as “deleted”.',
        style: TextStyle(color: stoopCream2(ctx)),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          style: TextButton.styleFrom(foregroundColor: stoopMute(ctx)),
          child: const Text('Cancel'),
        ),
        TextButton(
          key: const Key('stoop-comment-delete-confirm'),
          onPressed: () => Navigator.pop(ctx, true),
          style: TextButton.styleFrom(foregroundColor: stoopEmberText(ctx)),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  return ok == true;
}
