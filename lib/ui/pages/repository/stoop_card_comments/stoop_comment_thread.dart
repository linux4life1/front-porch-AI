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
import 'package:front_porch_ai/ui/pages/repository/stoop_card_comments/stoop_card_comments.dart';
import 'package:front_porch_ai/ui/pages/repository/stoop_glass.dart';

/// One comment, its creator reply (if any), and the Reply affordance or the
/// open reply composer when [replying].
class StoopCommentThread extends StatelessWidget {
  final StoopComment comment;
  final BackporchUser? user;
  final String? cardOwnerId;
  final bool canModerate;
  final DateTime Function() now;

  /// This thread's reply composer is the open one.
  final bool replying;
  final TextEditingController replyDraft;
  final bool replyPosting;
  final String? replyInlineError;

  final VoidCallback onDelete;
  final VoidCallback onReport;
  final VoidCallback onDeleteReply;
  final VoidCallback onReportReply;
  final VoidCallback onStartReply;
  final VoidCallback onPostReply;
  final VoidCallback onReplyDraftChanged;

  const StoopCommentThread({
    super.key,
    required this.comment,
    required this.user,
    required this.cardOwnerId,
    required this.canModerate,
    required this.now,
    required this.replying,
    required this.replyDraft,
    required this.replyPosting,
    required this.replyInlineError,
    required this.onDelete,
    required this.onReport,
    required this.onDeleteReply,
    required this.onReportReply,
    required this.onStartReply,
    required this.onPostReply,
    required this.onReplyDraftChanged,
  });

  @override
  Widget build(BuildContext context) {
    final canReply = stoopCanReplyToComment(
      comment: comment,
      user: user,
      cardOwnerId: cardOwnerId,
    );
    final reply = comment.reply;
    final hasLiveReply = reply != null && !reply.deleted;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StoopCommentRow(
          comment: comment,
          user: user,
          cardOwnerId: cardOwnerId,
          canModerate: canModerate,
          now: now,
          onDelete: onDelete,
          onReport: onReport,
        ),
        if (reply != null)
          Padding(
            padding: const EdgeInsets.only(left: 42, top: 8),
            child: StoopCommentReplyRow(
              parent: comment,
              reply: reply,
              user: user,
              cardOwnerId: cardOwnerId,
              canModerate: canModerate,
              now: now,
              onDelete: onDeleteReply,
              onReport: onReportReply,
            ),
          ),
        if (canReply && !hasLiveReply) ...[
          if (replying)
            Padding(
              padding: const EdgeInsets.only(left: 42, top: 8),
              child: StoopCommentReplyComposer(
                parent: comment,
                user: user!,
                draft: replyDraft,
                posting: replyPosting,
                inlineError: replyInlineError,
                onPost: onPostReply,
                onDraftChanged: onReplyDraftChanged,
              ),
            )
          else
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: 42),
                child: TextButton(
                  key: Key('stoop-comment-reply-${comment.id}'),
                  onPressed: onStartReply,
                  style: TextButton.styleFrom(
                    foregroundColor: stoopTealText(context),
                    padding: const EdgeInsets.symmetric(horizontal: 0),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Reply'),
                ),
              ),
            ),
        ],
      ],
    );
  }
}
