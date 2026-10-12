// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Character-detail Discussion block. Lives in this leaf so the detail page
// does not grow. Mock client only — never talks to prod.

import 'package:flutter/material.dart';

import 'package:front_porch_ai/services/backporch/backporch.dart';
import 'package:front_porch_ai/ui/pages/repository/stoop_card_comments/stoop_card_comments.dart';
import 'package:front_porch_ai/ui/pages/repository/stoop_collapsible.dart';
import 'package:front_porch_ai/ui/pages/repository/stoop_glass.dart';
import 'package:front_porch_ai/ui/pages/repository/stoop_report.dart';

export 'stoop_card_comments/stoop_card_discussion_section.dart';

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

  Future<void> _delete(StoopComment comment) async {
    final user = _user;
    if (user == null) return;
    final confirmed = await confirmStoopCommentDelete(
      context,
      title: 'Delete comment?',
    );
    if (!confirmed) return;
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
    final confirmed = await confirmStoopCommentDelete(
      context,
      title: 'Delete reply?',
    );
    if (!confirmed) return;
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

  @override
  Widget build(BuildContext context) {
    return StoopCollapsible(
      title: 'Discussion',
      initiallyExpanded: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          StoopCommentComposer(
            user: _user,
            canWrite: _canWrite,
            draft: _draft,
            posting: _posting,
            onNudgeSignIn: _nudgeSignIn,
            onNudgeVerify: _nudgeVerify,
            onPost: _post,
            onDraftChanged: () => setState(() {}),
          ),
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
              StoopCommentThread(
                comment: c,
                user: _user,
                cardOwnerId: widget.cardOwnerId,
                canModerate: widget.canModerate,
                now: widget.now,
                replying: _replyingToId == c.id,
                replyDraft: _replyDraft,
                replyPosting: _replyPosting,
                replyInlineError: _replyInlineError,
                onDelete: () => _delete(c),
                onReport: () => _report(c),
                onDeleteReply: () => _deleteReply(c),
                onReportReply: () => _reportReply(c),
                onStartReply: () => setState(() {
                  _replyingToId = c.id;
                  _replyInlineError = null;
                }),
                onPostReply: () => _postReply(c),
                onReplyDraftChanged: () => setState(() {}),
              ),
              const SizedBox(height: 12),
            ],
          ],
        ],
      ),
    );
  }
}
