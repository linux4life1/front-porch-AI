// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Character-detail Discussion block. Lives in this leaf so the detail page
// does not grow. Mock client only — never talks to prod.

part of 'stoop_card_comments.dart';

extension _StoopCardCommentsStateViews on _StoopCardCommentsState {
  Widget _composer(BuildContext context) {
    if (_user == null) {
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          key: const Key('stoop-comment-signin'),
          onPressed: _nudgeSignIn,
          style: TextButton.styleFrom(
            foregroundColor: stoopEmberText(context),
            padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
          ),
          child: const Text('Sign in to comment.'),
        ),
      );
    }
    if (!_canWrite) {
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          onPressed: _nudgeVerify,
          style: TextButton.styleFrom(
            foregroundColor: stoopEmberText(context),
            padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
          ),
          child: const Text('Confirm email to comment.'),
        ),
      );
    }
    final canPost = _draft.text.trim().isNotEmpty && !_posting;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StoopCreatorAvatar(
          assetId: _user!.avatarAssetId,
          name: _user!.displayName,
          size: 36,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: TextField(
            key: const Key('stoop-comment-field'),
            controller: _draft,
            maxLines: 4,
            minLines: 2,
            maxLength: kStoopCommentMaxLength,
            style: TextStyle(color: stoopCream(context), fontSize: 14),
            decoration: stoopInput(
              context,
              'Write a comment',
              counterText: _draft.text.length >= 900
                  ? '${_draft.text.length}/$kStoopCommentMaxLength'
                  : '',
            ),
            onChanged: (_) => rebuildState(() {}),
          ),
        ),
        const SizedBox(width: 10),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: StoopAmberButton(
            key: const Key('stoop-comment-post'),
            label: 'Post',
            busy: _posting,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            onPressed: canPost ? _post : null,
          ),
        ),
      ],
    );
  }

  Widget _thread(BuildContext context, StoopComment comment) {
    final canReply = stoopCanReplyToComment(
      comment: comment,
      user: _user,
      cardOwnerId: widget.cardOwnerId,
    );
    final reply = comment.reply;
    final hasLiveReply = reply != null && !reply.deleted;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _row(context, comment),
        if (reply != null)
          Padding(
            padding: const EdgeInsets.only(left: 42, top: 8),
            child: _replyRow(context, comment, reply),
          ),
        if (canReply && !hasLiveReply) ...[
          if (_replyingToId == comment.id)
            Padding(
              padding: const EdgeInsets.only(left: 42, top: 8),
              child: _replyComposer(context, comment),
            )
          else
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: 42),
                child: TextButton(
                  key: Key('stoop-comment-reply-${comment.id}'),
                  onPressed: () => rebuildState(() {
                    _replyingToId = comment.id;
                    _replyInlineError = null;
                  }),
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

  Widget _replyComposer(BuildContext context, StoopComment parent) {
    final canPost = _replyDraft.text.trim().isNotEmpty && !_replyPosting;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            StoopCreatorAvatar(
              assetId: _user!.avatarAssetId,
              name: _user!.displayName,
              size: 28,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                key: Key('stoop-comment-reply-field-${parent.id}'),
                controller: _replyDraft,
                maxLines: 3,
                minLines: 2,
                maxLength: kStoopCommentMaxLength,
                style: TextStyle(color: stoopCream(context), fontSize: 14),
                decoration: stoopInput(
                  context,
                  'Write a reply',
                  counterText: _replyDraft.text.length >= 900
                      ? '${_replyDraft.text.length}/$kStoopCommentMaxLength'
                      : '',
                ),
                onChanged: (_) => rebuildState(() {}),
              ),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: StoopAmberButton(
                key: Key('stoop-comment-reply-post-${parent.id}'),
                label: 'Post',
                busy: _replyPosting,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                onPressed: canPost ? () => _postReply(parent) : null,
              ),
            ),
          ],
        ),
        if (_replyInlineError != null) ...[
          const SizedBox(height: 6),
          Text(
            _replyInlineError!,
            style: TextStyle(color: stoopEmberText(context), fontSize: 13),
          ),
        ],
      ],
    );
  }

  Widget _replyRow(
    BuildContext context,
    StoopComment parent,
    StoopCommentReply reply,
  ) {
    final canDelete = stoopCanDeleteReply(
      reply: reply,
      user: _user,
      cardOwnerId: widget.cardOwnerId,
      canModerate: widget.canModerate,
    );
    final canReport = stoopCanReportReply(reply: reply, user: _user);
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
                    _creatorMark(context, parent.id),
                    const SizedBox(width: 8),
                    Text(
                      stoopCommentRelativeTime(reply.createdAt, widget.now()),
                      style: TextStyle(
                        color: stoopFaint(context),
                        fontSize: 12,
                      ),
                    ),
                    const Spacer(),
                    if (canDelete)
                      TextButton(
                        key: Key('stoop-comment-reply-delete-${parent.id}'),
                        onPressed: () => _deleteReply(parent),
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
                        onPressed: () => _reportReply(parent),
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

  Widget _creatorMark(BuildContext context, String parentId) {
    return Container(
      key: Key('stoop-comment-reply-creator-$parentId'),
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

  Widget _row(BuildContext context, StoopComment comment) {
    final canDelete = stoopCanDeleteComment(
      comment: comment,
      user: _user,
      cardOwnerId: widget.cardOwnerId,
      canModerate: widget.canModerate,
    );
    final canReport = stoopCanReportComment(comment: comment, user: _user);
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
                    stoopCommentRelativeTime(comment.createdAt, widget.now()),
                    style: TextStyle(color: stoopFaint(context), fontSize: 12),
                  ),
                  const Spacer(),
                  if (canDelete)
                    TextButton(
                      key: Key('stoop-comment-delete-${comment.id}'),
                      onPressed: () => _delete(comment),
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
                      onPressed: () => _report(comment),
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
