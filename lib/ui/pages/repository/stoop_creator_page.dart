// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/providers/auth_state.dart';
import 'package:front_porch_ai/services/backporch/backporch.dart';
import 'package:front_porch_ai/ui/pages/repository/stoop_card_detail_page.dart';
import 'package:front_porch_ai/ui/pages/repository/stoop_card_tile.dart';
import 'package:front_porch_ai/ui/pages/repository/stoop_glass.dart';
import 'package:front_porch_ai/ui/pages/repository/stoop_profile_header.dart';
import 'package:front_porch_ai/ui/pages/repository/stoop_verified_badge.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// A creator's public profile: the shared identity header (avatar, join date,
/// bio, links, lifetime stats) with Follow + Share, and a grid of their
/// approved cards.
class StoopCreatorPage extends StatefulWidget {
  final String creatorId;
  const StoopCreatorPage({super.key, required this.creatorId});

  @override
  State<StoopCreatorPage> createState() => _StoopCreatorPageState();
}

class _StoopCreatorPageState extends State<StoopCreatorPage> {
  final _api = BackporchApi();
  StoopCreator? _profile;
  bool _loading = true;
  String? _error;
  bool _following = false;
  int _followers = 0;
  bool _followBusy = false;
  StreamSubscription<StoopCardStats>? _statsSub;

  @override
  void initState() {
    super.initState();
    // Live vote/download counters on this creator's card grid.
    _statsSub = StoopMessageSocket.onCardStats.listen((s) {
      final cards = _profile?.cards;
      if (cards != null && s.applyTo(cards) && mounted) setState(() {});
    });
    _load();
  }

  @override
  void dispose() {
    _statsSub?.cancel();
    super.dispose();
  }

  String get _token => context.read<AuthState>().accessToken ?? '';

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final p = await _api.creatorProfile(_token, widget.creatorId);
      if (!mounted) return;
      setState(() {
        _profile = p;
        _following = p.following;
        _followers = p.followers;
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Couldn’t load this creator.';
          _loading = false;
        });
      }
    }
  }

  Future<void> _toggleFollow() async {
    final want = !_following;
    setState(() {
      _followBusy = true;
      _following = want;
      _followers += want ? 1 : -1;
    });
    try {
      final r = await _api.setFollow(_token, widget.creatorId, want);
      if (mounted) {
        setState(() {
          _following = r.following;
          _followers = r.followers;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _following = !want;
          _followers += want ? -1 : 1;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Follow failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _followBusy = false);
    }
  }

  void _openCard(StoopCard c) {
    showStoopDetail(context, c.id);
  }

  @override
  Widget build(BuildContext context) {
    final p = _profile;
    return Scaffold(
      backgroundColor: stoopBg0(context),
      appBar: AppBar(
        backgroundColor: stoopBg0(context),
        foregroundColor: stoopCream(context),
        elevation: 0,
        shape: Border(bottom: BorderSide(color: stoopBorder(context))),
        title: Row(
          children: [
            Flexible(
              child: Text(
                p?.displayName ?? 'Creator',
                style: stoopDisplay(context, size: 19),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (p != null)
              StoopVerifiedBadge(verification: p.verification, size: 18),
          ],
        ),
      ),
      body: _loading
          ? const StoopLamp()
          : _error != null || p == null
          ? stoopEmpty(context, glyph: '🌙', title: _error ?? 'Not found')
          : _content(p),
    );
  }

  Widget _content(StoopCreator p) {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: _header(p)),
        if (p.cards.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: stoopEmpty(
              context,
              glyph: '🏮',
              title: 'No published cards yet',
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 230,
                childAspectRatio: 0.64,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
              ),
              delegate: SliverChildBuilderDelegate(
                (_, i) => StoopCardTile(
                  card: p.cards[i],
                  onTap: () => _openCard(p.cards[i]),
                ),
                childCount: p.cards.length,
              ),
            ),
          ),
      ],
    );
  }

  Widget _header(StoopCreator p) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: StoopProfileHeader(
        creator: p,
        followers: _followers,
        actions: [
          if (!p.isMe)
            _following
                ? OutlinedButton(
                    onPressed: _followBusy ? null : _toggleFollow,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: stoopTealText(context),
                      side: BorderSide(
                        color: AppColors.stoopTeal.withValues(alpha: 0.45),
                      ),
                    ),
                    child: const Text('Following'),
                  )
                : StoopAmberButton(
                    label: 'Follow',
                    onPressed: _followBusy ? null : _toggleFollow,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 10,
                    ),
                  ),
          OutlinedButton.icon(
            onPressed: () => stoopCopyCreatorLink(
              context,
              id: p.id,
              displayName: p.displayName,
            ),
            icon: const Icon(Icons.link_rounded, size: 16),
            label: const Text('Share'),
            style: OutlinedButton.styleFrom(
              foregroundColor: stoopCream2(context),
              side: BorderSide(color: stoopBorderHi(context)),
            ),
          ),
        ],
      ),
    );
  }
}
