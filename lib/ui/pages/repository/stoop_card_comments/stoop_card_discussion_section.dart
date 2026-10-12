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
import 'package:front_porch_ai/ui/pages/repository/stoop_card_comments.dart';
import 'package:front_porch_ai/ui/pages/repository/stoop_comments_switch.dart';

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
