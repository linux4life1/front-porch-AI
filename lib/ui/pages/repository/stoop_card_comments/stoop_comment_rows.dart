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
import 'package:front_porch_ai/ui/pages/repository/stoop_verified_badge.dart';

/// One top-level Discussion comment: avatar, handle, time, Delete / Report.
class StoopCommentRow extends StatelessWidget {
  final StoopComment comment;
  final BackporchUser? user;
  final String? cardOwnerId;
  final bool canModerate;
  final DateTime Function() now;
  final VoidCallback onDelete;
  final VoidCallback onReport;

  const StoopCommentRow({
    super.key,
    required this.comment,
    required this.user,
    required this.cardOwnerId,
    required this.canModerate,
    required this.now,
    required this.onDelete,
    required this.onReport,
  });

  @override
  Widget build(BuildContext context) {
    final canDelete = stoopCanDeleteComment(
      comment: comment,
      user: user,
      cardOwnerId: cardOwnerId,
      canModerate: canModerate,
    );
    final canReport = stoopCanReportComment(comment: comment, user: user);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StoopCreatorAvatar(
          assetId: comment.authorAvatarAssetId,
          name: comment.displayName,
          size: 32,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      '@${comment.displayName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: stoopTealText(context),
                        fontWeight: FontWeight.w600,
                        fontSize: 13.5,
                      ),
                    ),
                  ),
                  StoopVerifiedBadge(
                    verification: comment.verification,
                    size: 13,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    stoopCommentRelativeTime(comment.createdAt, now()),
                    style: TextStyle(color: stoopFaint(context), fontSize: 12),
                  ),
                  const Spacer(),
                  if (canDelete)
                    TextButton(
                      key: Key('stoop-comment-delete-${comment.id}'),
                      onPressed: onDelete,
                      style: TextButton.styleFrom(
                        foregroundColor: stoopEmberText(context),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text('Delete'),
                    ),
                  if (canReport)
                    TextButton(
                      key: Key('stoop-comment-report-${comment.id}'),
                      onPressed: onReport,
                      style: TextButton.styleFrom(
                        foregroundColor: stoopEmberText(context),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text('Report'),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              if (comment.deleted)
                Text(
                  'deleted',
                  style: TextStyle(
                    color: stoopMute(context),
                    fontStyle: FontStyle.italic,
                    fontSize: 13.5,
                  ),
                )
              else
                Text(
                  comment.body,
                  style: TextStyle(
                    color: stoopCream2(context),
                    height: 1.45,
                    fontSize: 14,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The card creator's reply under [parent], marked "Creator".
class StoopCommentReplyRow extends StatelessWidget {
  final StoopComment parent;
  final StoopCommentReply reply;
  final BackporchUser? user;
  final String? cardOwnerId;
  final bool canModerate;
  final DateTime Function() now;
  final VoidCallback onDelete;
  final VoidCallback onReport;

  const StoopCommentReplyRow({
    super.key,
    required this.parent,
    required this.reply,
    required this.user,
    required this.cardOwnerId,
    required this.canModerate,
    required this.now,
    required this.onDelete,
    required this.onReport,
  });

  @override
  Widget build(BuildContext context) {
    final canDelete = stoopCanDeleteReply(
      reply: reply,
      user: user,
      cardOwnerId: cardOwnerId,
      canModerate: canModerate,
    );
    final canReport = stoopCanReportReply(reply: reply, user: user);
    return KeyedSubtree(
      key: Key('stoop-comment-reply-row-${parent.id}'),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StoopCreatorAvatar(
            assetId: reply.authorAvatarAssetId,
            name: reply.displayName,
            size: 28,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        '@${reply.displayName}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: stoopTealText(context),
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    StoopVerifiedBadge(
                      verification: reply.verification,
                      size: 12,
                    ),
                    const SizedBox(width: 6),
                    _creatorMark(context),
                    const SizedBox(width: 8),
                    Text(
                      stoopCommentRelativeTime(reply.createdAt, now()),
                      style: TextStyle(
                        color: stoopFaint(context),
                        fontSize: 12,
                      ),
                    ),
                    const Spacer(),
                    if (canDelete)
                      TextButton(
                        key: Key('stoop-comment-reply-delete-${parent.id}'),
                        onPressed: onDelete,
                        style: TextButton.styleFrom(
                          foregroundColor: stoopEmberText(context),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text('Delete'),
                      ),
                    if (canReport)
                      TextButton(
                        key: Key('stoop-comment-reply-report-${parent.id}'),
                        onPressed: onReport,
                        style: TextButton.styleFrom(
                          foregroundColor: stoopEmberText(context),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text('Report'),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                if (reply.deleted)
                  Text(
                    'deleted',
                    style: TextStyle(
                      color: stoopMute(context),
                      fontStyle: FontStyle.italic,
                      fontSize: 13.5,
                    ),
                  )
                else
                  Text(
                    reply.body,
                    style: TextStyle(
                      color: stoopCream2(context),
                      height: 1.45,
                      fontSize: 14,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _creatorMark(BuildContext context) {
    return Container(
      key: Key('stoop-comment-reply-creator-${parent.id}'),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
      decoration: BoxDecoration(
        color: stoopTealSoft(context),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: stoopTealText(context).withValues(alpha: 0.35),
        ),
      ),
      child: Text(
        'Creator',
        style: TextStyle(
          color: stoopTealText(context),
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
