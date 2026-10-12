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

import 'package:front_porch_ai/services/backporch/backporch.dart';
import 'package:front_porch_ai/ui/pages/repository/stoop_glass.dart';
import 'package:front_porch_ai/ui/pages/repository/stoop_profile_header.dart';

/// Top-level Discussion composer: a sign-in / confirm-email nudge when the
/// viewer cannot write, else avatar + field + Post.
class StoopCommentComposer extends StatelessWidget {
  final BackporchUser? user;
  final bool canWrite;
  final TextEditingController draft;
  final bool posting;
  final VoidCallback onNudgeSignIn;
  final VoidCallback onNudgeVerify;
  final VoidCallback onPost;

  /// Fired on every keystroke so the owner rebuilds (counter + Post enable).
  final VoidCallback onDraftChanged;

  const StoopCommentComposer({
    super.key,
    required this.user,
    required this.canWrite,
    required this.draft,
    required this.posting,
    required this.onNudgeSignIn,
    required this.onNudgeVerify,
    required this.onPost,
    required this.onDraftChanged,
  });

  @override
  Widget build(BuildContext context) {
    final user = this.user;
    if (user == null) {
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          key: const Key('stoop-comment-signin'),
          onPressed: onNudgeSignIn,
          style: TextButton.styleFrom(
            foregroundColor: stoopEmberText(context),
            padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
          ),
          child: const Text('Sign in to comment.'),
        ),
      );
    }
    if (!canWrite) {
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          onPressed: onNudgeVerify,
          style: TextButton.styleFrom(
            foregroundColor: stoopEmberText(context),
            padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
          ),
          child: const Text('Confirm email to comment.'),
        ),
      );
    }
    final canPost = draft.text.trim().isNotEmpty && !posting;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StoopCreatorAvatar(
          assetId: user.avatarAssetId,
          name: user.displayName,
          size: 36,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: TextField(
            key: const Key('stoop-comment-field'),
            controller: draft,
            maxLines: 4,
            minLines: 2,
            maxLength: kStoopCommentMaxLength,
            style: TextStyle(color: stoopCream(context), fontSize: 14),
            decoration: stoopInput(
              context,
              'Write a comment',
              counterText: draft.text.length >= 900
                  ? '${draft.text.length}/$kStoopCommentMaxLength'
                  : '',
            ),
            onChanged: (_) => onDraftChanged(),
          ),
        ),
        const SizedBox(width: 10),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: StoopAmberButton(
            key: const Key('stoop-comment-post'),
            label: 'Post',
            busy: posting,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            onPressed: canPost ? onPost : null,
          ),
        ),
      ],
    );
  }
}
