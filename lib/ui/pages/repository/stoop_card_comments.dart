// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Character-detail Discussion block. Lives in this leaf so the detail page
// does not grow. Mock client only — never talks to prod.

import 'package:flutter/material.dart';

import 'package:front_porch_ai/services/backporch/backporch.dart';
import 'package:front_porch_ai/ui/pages/repository/stoop_collapsible.dart';
import 'package:front_porch_ai/ui/pages/repository/stoop_comments_switch.dart';
import 'package:front_porch_ai/ui/pages/repository/stoop_glass.dart';
import 'package:front_porch_ai/ui/pages/repository/stoop_profile_header.dart';
import 'package:front_porch_ai/ui/pages/repository/stoop_report.dart';
import 'package:front_porch_ai/ui/pages/repository/stoop_verified_badge.dart';

/// Hosts the Discussion block + owner kill switch.
///
/// Default OFF: renders nothing unless this card opted in
/// ([commentsEnabled] or a [StoopCommentsOptIn] published/live flag).
/// Off hides the composer AND the list. The card owner always sees the
/// switch so they can turn discussion on after upload. Turning off locks
/// (hides) without wiping hub rows.
class StoopCardDiscussionSection extends StatefulWidget {
  final String cardId;
  final String? cardOwnerId;
  final BackporchUser? user;
  final StoopCommentsClient client;
  final bool commentsEnabled;
  final bool commentsLocked;
  final StoopCommentsOptIn? optInStore;
  final bool canModerate;
  final DateTime Function() now;
  final Future<({bool commentsEnabled, bool commentsLocked})> Function({
    bool? commentsEnabled,
    bool? commentsLocked,
  })?
  persistFlags;

  const StoopCardDiscussionSection({
    super.key,
    required this.cardId,
    this.cardOwnerId,
    required this.user,
    required this.client,
    this.commentsEnabled = false,
    this.commentsLocked = false,
    this.optInStore,
    this.persistFlags,
    this.canModerate = false,
    this.now = DateTime.now,
  });

  @override
  State<StoopCardDiscussionSection> createState() =>
      _StoopCardDiscussionSectionState();
}

class _StoopCardDiscussionSectionState
    extends State<StoopCardDiscussionSection> {
  late bool _live;
  late bool _published;

  StoopCommentsOptIn get _store =>
      widget.optInStore ?? StoopCommentsOptIn.instance;

  @override
  void initState() {
    super.initState();
    _published = _store.published(
      widget.cardId,
      fromCard: widget.commentsEnabled,
    );
    _live = widget.commentsLocked
        ? false
        : _store.live(widget.cardId, fromCard: widget.commentsEnabled);
  }

  bool get _isOwner =>
      widget.user != null &&
      widget.cardOwnerId != null &&
      widget.user!.id == widget.cardOwnerId;

  Future<void> _setLive(bool next) async {
    final prev = _live;
    setState(() {
      _live = next;
      _store.setLive(widget.cardId, next);
    });
    final persist = widget.persistFlags;
    if (persist == null) return;
    try {
      // First-time on: persist the opt-in. Later off: lock (hide, keep rows).
      final flags = next
          ? await persist(commentsEnabled: true, commentsLocked: false)
          : (_published
                ? await persist(commentsLocked: true)
                : await persist(commentsEnabled: false));
      if (!mounted) return;
      if (flags.commentsEnabled != true) {
        setState(() {
          _published = false;
          _live = false;
        });
        return;
      }
      setState(() {
        _published = true;
        _live = flags.commentsLocked != true;
      });
    } on BackporchApiException catch (e) {
      if (!mounted) return;
      if (e.statusCode == 404) {
        setState(() {
          _published = false;
          _live = false;
        });
        return;
      }
      setState(() {
        _live = prev;
        _store.setLive(widget.cardId, prev);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _live = prev;
        _store.setLive(widget.cardId, prev);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final showSwitch = _isOwner;
    if (!showSwitch && !_live) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showSwitch) ...[
          StoopCommentsSwitch(
            key: const Key('stoop-comments-kill-switch'),
            value: _live,
            liveKill: true,
            onChanged: _setLive,
          ),
          if (_live) const SizedBox(height: 10),
        ],
        if (_live)
          StoopCardComments(
            cardId: widget.cardId,
            cardOwnerId: widget.cardOwnerId,
            user: widget.user,
            client: widget.client,
            canModerate: widget.canModerate,
            now: widget.now,
          ),
      ],
    );
  }
}

/// Discussion list + composer for one character card.
class StoopCardComments extends StatefulWidget {
  final String cardId;
  final String? cardOwnerId;
  final BackporchUser? user;
  final StoopCommentsClient client;

  /// Hub / moderator override for tests (in addition to [BackporchUser.isModerator]).
  final bool canModerate;

  /// Clock seam so goldens and relative-time tests stay still.
  final DateTime Function() now;

  const StoopCardComments({
    super.key,
    required this.cardId,
    this.cardOwnerId,
    required this.user,
    required this.client,
    this.canModerate = false,
    this.now = DateTime.now,
  });

  @override
  State<StoopCardComments> createState() => _StoopCardCommentsState();
}

class _StoopCardCommentsState extends State<StoopCardComments> {
  final _draft = TextEditingController();
  final _replyDraft = TextEditingController();
  List<StoopComment> _comments = const [];
  bool _loading = true;
  bool _posting = false;
  bool _replyPosting = false;
  bool _apiSaysUnverified = false;
  String? _inlineError;
  String? _replyInlineError;
  String? _replyingToId;

  BackporchUser? get _user => widget.user;

  bool get _canWrite => stoopCanComment(_user) && !_apiSaysUnverified;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _draft.dispose();
    _replyDraft.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final items = await widget.client.list(widget.cardId);
      if (!mounted) return;
      setState(() {
        _comments = _newestFirst(items);
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  List<StoopComment> _newestFirst(List<StoopComment> items) {
    final copy = [...items]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return copy;
  }

  void _replace(StoopComment updated) {
    _comments = [
      for (final c in _comments)
        if (c.id == updated.id) updated else c,
    ];
  }

  Future<void> _post() async {
    final text = _draft.text;
    if (text.trim().isEmpty || _posting) return;
    if (!stoopCanComment(_user)) {
      setState(() {
        _apiSaysUnverified = _user != null;
        _inlineError = _user == null
            ? 'Sign in to comment.'
            : 'Confirm email to comment.';
      });
      return;
    }
    setState(() {
      _posting = true;
      _inlineError = null;
    });
    try {
      final created = await widget.client.create(
        cardId: widget.cardId,
        body: text,
        author: _user!,
      );
      if (!mounted) return;
      setState(() {
        _comments = _newestFirst([created, ..._comments]);
        _draft.clear();
        _posting = false;
        _inlineError = null;
      });
    } on BackporchApiException catch (e) {
      if (!mounted) return;
      if (e.code == 'email_not_verified') {
        setState(() {
          _apiSaysUnverified = true;
          _posting = false;
          _inlineError = null;
        });
        return;
      }
      final msg = stoopCommentFailureMessage(e);
      final rateLimited =
          e.statusCode == 429 ||
          e.code == 'too_many_comments' ||
          e.code == 'too_many_reports';
      setState(() {
        _posting = false;
        if (!rateLimited) _inlineError = msg;
      });
      if (rateLimited) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(msg)));
      }
      // 409 / 429: draft stays in [_draft].
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _posting = false;
        _inlineError = stoopCommentFailureMessage(e);
      });
    }
  }

  Future<void> _postReply(StoopComment parent) async {
    final text = _replyDraft.text;
    if (text.trim().isEmpty || _replyPosting) return;
    if (!stoopCanComment(_user)) {
      setState(() {
        _apiSaysUnverified = _user != null;
        _replyInlineError = _user == null
            ? 'Sign in to comment.'
            : 'Confirm email to comment.';
      });
      return;
    }
    setState(() {
      _replyPosting = true;
      _replyInlineError = null;
    });
    try {
      final updated = await widget.client.createReply(
        cardId: widget.cardId,
        commentId: parent.id,
        body: text,
        author: _user!,
        cardOwnerId: widget.cardOwnerId,
      );
      if (!mounted) return;
      setState(() {
        _replace(updated);
        _replyDraft.clear();
        _replyingToId = null;
        _replyPosting = false;
        _replyInlineError = null;
      });
    } on BackporchApiException catch (e) {
      if (!mounted) return;
      if (e.code == 'email_not_verified') {
        setState(() {
          _apiSaysUnverified = true;
          _replyPosting = false;
          _replyInlineError = null;
          _replyingToId = null;
        });
        return;
      }
      final msg = stoopCommentFailureMessage(e);
      final rateLimited =
          e.statusCode == 429 ||
          e.code == 'too_many_comments' ||
          e.code == 'too_many_reports';
      setState(() {
        _replyPosting = false;
        if (!rateLimited) _replyInlineError = msg;
      });
      if (rateLimited) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(msg)));
      }
      // 409 / 429: reply draft stays in [_replyDraft].
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _replyPosting = false;
        _replyInlineError = stoopCommentFailureMessage(e);
      });
    }
  }

  Future<bool> _confirmDelete({required String title}) async {
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

  Future<void> _delete(StoopComment comment) async {
    final user = _user;
    if (user == null) return;
    if (!await _confirmDelete(title: 'Delete comment?')) return;
    try {
      final tombstone = await widget.client.delete(
        cardId: widget.cardId,
        commentId: comment.id,
        actor: user,
        cardOwnerId: widget.cardOwnerId,
        canModerate: widget.canModerate,
      );
      if (!mounted) return;
      setState(() => _replace(tombstone));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(stoopCommentFailureMessage(e))));
    }
  }

  Future<void> _deleteReply(StoopComment comment) async {
    final user = _user;
    if (user == null) return;
    if (!await _confirmDelete(title: 'Delete reply?')) return;
    try {
      final tombstone = await widget.client.deleteReply(
        cardId: widget.cardId,
        commentId: comment.id,
        actor: user,
        cardOwnerId: widget.cardOwnerId,
        canModerate: widget.canModerate,
      );
      if (!mounted) return;
      setState(() => _replace(tombstone));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(stoopCommentFailureMessage(e))));
    }
  }

  Future<void> _report(StoopComment comment) async {
    final user = _user;
    if (!stoopCanReportComment(comment: comment, user: user)) return;
    final result = await showDialog<({String category, String reason})>(
      context: context,
      builder: (_) => const StoopReportDialog(title: 'Report this comment'),
    );
    if (result == null) return;
    try {
      await widget.client.report(
        cardId: widget.cardId,
        commentId: comment.id,
        actor: user!,
        category: result.category,
        reason: result.reason,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Reported. Thanks — a moderator will review it.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(stoopCommentFailureMessage(e))));
    }
  }

  Future<void> _reportReply(StoopComment comment) async {
    final user = _user;
    final reply = comment.reply;
    if (reply == null) return;
    if (!stoopCanReportReply(reply: reply, user: user)) return;
    final result = await showDialog<({String category, String reason})>(
      context: context,
      builder: (_) => const StoopReportDialog(title: 'Report this reply'),
    );
    if (result == null) return;
    try {
      await widget.client.reportReply(
        cardId: widget.cardId,
        commentId: comment.id,
        actor: user!,
        category: result.category,
        reason: result.reason,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Reported. Thanks — a moderator will review it.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(stoopCommentFailureMessage(e))));
    }
  }

  void _nudgeVerify() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Confirm your email to comment. Check your inbox, or resend from Account.',
        ),
      ),
    );
  }

  void _nudgeSignIn() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Sign in from Account to comment.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StoopCollapsible(
      title: 'Discussion',
      initiallyExpanded: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _composer(context),
          if (_inlineError != null) ...[
            const SizedBox(height: 8),
            Text(
              _inlineError!,
              style: TextStyle(color: stoopEmberText(context), fontSize: 13),
            ),
          ],
          const SizedBox(height: 16),
          if (_loading)
            const StoopLamp()
          else if (_comments.isEmpty)
            Text(
              'No comments yet.',
              style: TextStyle(color: stoopMute(context), fontSize: 14),
            )
          else ...[
            for (final c in _comments) ...[
              _thread(context, c),
              const SizedBox(height: 12),
            ],
          ],
        ],
      ),
    );
  }

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
            onChanged: (_) => setState(() {}),
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
                  onPressed: () => setState(() {
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
                onChanged: (_) => setState(() {}),
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
