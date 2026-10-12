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

/// The creator's one-reply composer under [parent].
class StoopCommentReplyComposer extends StatelessWidget {
  final StoopComment parent;
  final BackporchUser user;
  final TextEditingController draft;
  final bool posting;
  final String? inlineError;
  final VoidCallback onPost;

  /// Fired on every keystroke so the owner rebuilds (counter + Post enable).
  final VoidCallback onDraftChanged;

  const StoopCommentReplyComposer({
    super.key,
    required this.parent,
    required this.user,
    required this.draft,
    required this.posting,
    required this.inlineError,
    required this.onPost,
    required this.onDraftChanged,
  });

  @override
  Widget build(BuildContext context) {
    final canPost = draft.text.trim().isNotEmpty && !posting;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            StoopCreatorAvatar(
              assetId: user.avatarAssetId,
              name: user.displayName,
              size: 28,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                key: Key('stoop-comment-reply-field-${parent.id}'),
                controller: draft,
                maxLines: 3,
                minLines: 2,
                maxLength: kStoopCommentMaxLength,
                style: TextStyle(color: stoopCream(context), fontSize: 14),
                decoration: stoopInput(
                  context,
                  'Write a reply',
                  counterText: draft.text.length >= 900
                      ? '${draft.text.length}/$kStoopCommentMaxLength'
                      : '',
                ),
                onChanged: (_) => onDraftChanged(),
              ),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: StoopAmberButton(
                key: Key('stoop-comment-reply-post-${parent.id}'),
                label: 'Post',
                busy: posting,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                onPressed: canPost ? onPost : null,
              ),
            ),
          ],
        ),
        if (inlineError != null) ...[
          const SizedBox(height: 6),
          Text(
            inlineError!,
            style: TextStyle(color: stoopEmberText(context), fontSize: 13),
          ),
        ],
      ],
    );
  }
}
