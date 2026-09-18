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

part 'stoop_card_comments.actions.dart';
part 'stoop_card_comments.views.dart';

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

  /// setState is protected, so the parts below cannot call it. Same bridge
  /// settings_page.dart exposes for the same reason.
  void rebuildState(VoidCallback fn) => setState(fn);

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
}
