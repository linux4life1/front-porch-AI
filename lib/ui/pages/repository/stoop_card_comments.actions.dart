// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Character-detail Discussion block. Lives in this leaf so the detail page
// does not grow. Mock client only — never talks to prod.

part of 'stoop_card_comments.dart';

extension _StoopCardCommentsStateActions on _StoopCardCommentsState {
  Future<void> _post() async {
    final text = _draft.text;
    if (text.trim().isEmpty || _posting) return;
    if (!stoopCanComment(_user)) {
      rebuildState(() {
        _apiSaysUnverified = _user != null;
        _inlineError = _user == null
            ? 'Sign in to comment.'
            : 'Confirm email to comment.';
      });
      return;
    }
    rebuildState(() {
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
      rebuildState(() {
        _comments = _newestFirst([created, ..._comments]);
        _draft.clear();
        _posting = false;
        _inlineError = null;
      });
    } on BackporchApiException catch (e) {
      if (!mounted) return;
      if (e.code == 'email_not_verified') {
        rebuildState(() {
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
      rebuildState(() {
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
      rebuildState(() {
        _posting = false;
        _inlineError = stoopCommentFailureMessage(e);
      });
    }
  }

  Future<void> _postReply(StoopComment parent) async {
    final text = _replyDraft.text;
    if (text.trim().isEmpty || _replyPosting) return;
    if (!stoopCanComment(_user)) {
      rebuildState(() {
        _apiSaysUnverified = _user != null;
        _replyInlineError = _user == null
            ? 'Sign in to comment.'
            : 'Confirm email to comment.';
      });
      return;
    }
    rebuildState(() {
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
      rebuildState(() {
        _replace(updated);
        _replyDraft.clear();
        _replyingToId = null;
        _replyPosting = false;
        _replyInlineError = null;
      });
    } on BackporchApiException catch (e) {
      if (!mounted) return;
      if (e.code == 'email_not_verified') {
        rebuildState(() {
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
      rebuildState(() {
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
      rebuildState(() {
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
      rebuildState(() => _replace(tombstone));
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
      rebuildState(() => _replace(tombstone));
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
}
