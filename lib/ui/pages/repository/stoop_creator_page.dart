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
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// A creator's public profile: follower count, a Follow button, and a grid of
/// their approved cards.
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
      backgroundColor: AppColors.backgroundOf(context),
      appBar: AppBar(
        backgroundColor: AppColors.surfaceOf(context),
        foregroundColor: AppColors.textPrimary(context),
        title: Text(p?.displayName ?? 'Creator'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null || p == null
          ? Center(
              child: Text(
                _error ?? 'Not found',
                style: TextStyle(color: AppColors.textTertiary(context)),
              ),
            )
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
            child: Center(
              child: Text(
                'No published characters yet.',
                style: TextStyle(color: AppColors.textTertiary(context)),
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 168,
                childAspectRatio: 0.66,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
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
    final accent = AppColors.resolve(context, Colors.tealAccent, Colors.teal);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Row(
        children: [
          CircleAvatar(
            radius: 30,
            backgroundColor: AppColors.surfaceContainerOf(context),
            child: Text(
              p.displayName.isNotEmpty
                  ? p.displayName.characters.first.toUpperCase()
                  : '?',
              style: TextStyle(
                color: AppColors.textPrimary(context),
                fontWeight: FontWeight.bold,
                fontSize: 22,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.displayName,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary(context),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$_followers ${_followers == 1 ? 'follower' : 'followers'} · '
                  '${p.cards.length} ${p.cards.length == 1 ? 'character' : 'characters'}',
                  style: TextStyle(color: AppColors.textTertiary(context)),
                ),
              ],
            ),
          ),
          if (!p.isMe) ...[
            const SizedBox(width: 12),
            _following
                ? OutlinedButton(
                    onPressed: _followBusy ? null : _toggleFollow,
                    child: const Text('Following'),
                  )
                : FilledButton(
                    onPressed: _followBusy ? null : _toggleFollow,
                    style: FilledButton.styleFrom(backgroundColor: accent),
                    child: Text(
                      'Follow',
                      style: TextStyle(color: AppColors.background),
                    ),
                  ),
          ],
        ],
      ),
    );
  }
}
