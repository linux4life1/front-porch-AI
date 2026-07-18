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
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/providers/auth_state.dart';
import 'package:front_porch_ai/services/backporch/backporch.dart';
import 'package:front_porch_ai/ui/pages/repository/stoop_avatar.dart';
import 'package:front_porch_ai/ui/pages/repository/stoop_card_detail_page.dart';
import 'package:front_porch_ai/ui/pages/repository/stoop_card_tile.dart';
import 'package:front_porch_ai/ui/pages/repository/stoop_glass.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// The community browse experience: Mod's Picks, a Following row, and the main
/// grid with smart search (`@creator`, `#tag`, or a name) and sort/type filters.
class StoopBrowseView extends StatefulWidget {
  const StoopBrowseView({super.key});

  @override
  State<StoopBrowseView> createState() => _StoopBrowseViewState();
}

class _StoopBrowseViewState extends State<StoopBrowseView> {
  final _api = BackporchApi();
  final _search = TextEditingController();
  final _scroll = ScrollController();

  String _sort = 'newest';
  String _type = 'all';
  String _query = '';

  List<StoopCard> _picks = const [];
  List<StoopCard> _following = const [];
  List<StoopCard> _groups = const [];
  final List<StoopCard> _grid = [];
  int _page = 0;
  bool _hasMore = true;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  StreamSubscription<StoopCardStats>? _statsSub;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _statsSub = StoopMessageSocket.onCardStats.listen(_applyCardStats);
    _loadAll();
  }

  @override
  void dispose() {
    _statsSub?.cancel();
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // Someone voted on or downloaded a card somewhere on The Stoop — tick the
  // counters on any tile currently showing it (grid, rows, and the hero, which
  // derives from these lists).
  void _applyCardStats(StoopCardStats s) {
    var changed = false;
    for (final cards in [_grid, _picks, _following, _groups]) {
      changed = s.applyTo(cards) || changed;
    }
    if (changed && mounted) setState(() {});
  }

  String? get _token => context.read<AuthState>().accessToken;

  Future<void> _loadAll() async {
    final token = _token;
    if (token == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Picks + Following are only shown on the default (unsearched) view.
      final showRows = _query.isEmpty;
      final results = await Future.wait([
        _api.browse(
          accessToken: token,
          sort: _sort,
          type: _type,
          q: _query,
          page: 0,
        ),
        showRows
            ? _api.browse(accessToken: token, pick: true, take: 12)
            : Future.value(const StoopBrowsePage(total: 0, page: 0, items: [])),
        showRows
            ? _api.browse(
                accessToken: token,
                following: true,
                sort: 'newest',
                take: 12,
              )
            : Future.value(const StoopBrowsePage(total: 0, page: 0, items: [])),
        // A dedicated Groups row (multi-character cards), shown on the default
        // view alongside Picks/Following.
        showRows
            ? _api.browse(
                accessToken: token,
                type: 'group',
                sort: 'newest',
                take: 12,
              )
            : Future.value(const StoopBrowsePage(total: 0, page: 0, items: [])),
      ]);
      if (!mounted) return;
      setState(() {
        _grid
          ..clear()
          ..addAll(results[0].items);
        _page = 0;
        _hasMore = results[0].items.length >= 24;
        _picks = results[1].items;
        _following = results[2].items;
        _groups = results[3].items;
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Couldn’t load The Stoop. Pull to retry.';
          _loading = false;
        });
      }
    }
  }

  Future<void> _loadMore() async {
    final token = _token;
    if (token == null || _loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final next = await _api.browse(
        accessToken: token,
        sort: _sort,
        type: _type,
        q: _query,
        page: _page + 1,
      );
      if (!mounted) return;
      setState(() {
        _grid.addAll(next.items);
        _page += 1;
        _hasMore = next.items.length >= 24;
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _onScroll() {
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 400) {
      _loadMore();
    }
  }

  void _applySearch(String value) {
    setState(() => _query = value.trim());
    _loadAll();
  }

  void _openCard(StoopCard c) {
    showStoopDetail(context, c.id);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _searchBar(),
        Expanded(child: _content()),
      ],
    );
  }

  Widget _content() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return _centered(Icons.cloud_off_outlined, _error!, retry: true);
    }
    final featured = _query.isEmpty
        ? (_picks.isNotEmpty
              ? _picks.first
              : (_grid.isNotEmpty ? _grid.first : null))
        : null;
    return RefreshIndicator(
      onRefresh: _loadAll,
      child: CustomScrollView(
        controller: _scroll,
        slivers: [
          if (featured != null) _heroSliver(featured),
          if (_picks.isNotEmpty) _carousel('⭐ Mod’s Picks', _picks),
          if (_following.isNotEmpty)
            _carousel('From creators you follow', _following),
          if (_groups.isNotEmpty) _carousel('👥 Groups', _groups),
          SliverToBoxAdapter(child: _browseHeader()),
          if (_grid.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _centered(Icons.search_off, 'No characters match.'),
            )
          else
            _gridSliver(),
          if (_loadingMore)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
    );
  }

  Widget _searchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: TextField(
        controller: _search,
        textInputAction: TextInputAction.search,
        onSubmitted: _applySearch,
        style: TextStyle(color: AppColors.textPrimary(context)),
        decoration: InputDecoration(
          hintText: 'Search name, @creator, or #tag',
          hintStyle: TextStyle(color: AppColors.textTertiary(context)),
          prefixIcon: Icon(
            Icons.search,
            color: AppColors.iconSecondary(context),
          ),
          suffixIcon: _query.isEmpty
              ? null
              : IconButton(
                  icon: Icon(
                    Icons.close,
                    color: AppColors.iconSecondary(context),
                  ),
                  onPressed: () {
                    _search.clear();
                    _applySearch('');
                  },
                ),
          filled: true,
          fillColor: AppColors.surfaceContainerOf(context),
          contentPadding: const EdgeInsets.symmetric(vertical: 4),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: AppColors.borderOf(context)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: AppColors.borderOf(context)),
          ),
        ),
      ),
    );
  }

  Widget _browseHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          Text(
            _query.isEmpty ? 'Browse all' : 'Results',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary(context),
            ),
          ),
          const Spacer(),
          _sortMenu(),
          const SizedBox(width: 8),
          _typeToggle(),
        ],
      ),
    );
  }

  Widget _sortMenu() {
    const labels = {'newest': 'Newest', 'top': 'Top', 'downloads': 'Downloads'};
    return PopupMenuButton<String>(
      initialValue: _sort,
      onSelected: (v) {
        setState(() => _sort = v);
        _loadAll();
      },
      itemBuilder: (_) => labels.entries
          .map((e) => PopupMenuItem(value: e.key, child: Text(e.value)))
          .toList(),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            labels[_sort]!,
            style: TextStyle(
              color: AppColors.textSecondary(context),
              fontSize: 13,
            ),
          ),
          Icon(Icons.arrow_drop_down, color: AppColors.iconSecondary(context)),
        ],
      ),
    );
  }

  Widget _typeToggle() {
    return SegmentedButton<String>(
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 12)),
      ),
      segments: const [
        ButtonSegment(value: 'all', label: Text('All')),
        ButtonSegment(value: 'solo', label: Text('Singles')),
        ButtonSegment(value: 'group', label: Text('Groups')),
      ],
      selected: {_type},
      showSelectedIcon: false,
      onSelectionChanged: (s) {
        setState(() => _type = s.first);
        _loadAll();
      },
    );
  }

  // The spotlight: the top pick. A blurred fill of its art backs a SHARP
  // portrait shown at its true aspect — so portrait card art never gets
  // stretched across the wide banner.
  SliverToBoxAdapter _heroSliver(StoopCard card) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: GestureDetector(
          onTap: () => _openCard(card),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: stoopAccent(context).withValues(alpha: 0.3),
                  blurRadius: 32,
                  spreadRadius: -8,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: SizedBox(
                height: 200,
                width: double.infinity,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Blurred, darkened fill of the same art.
                    StoopAvatar(assetId: card.primaryAssetId),
                    BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
                      child: Container(
                        color: Colors.black.withValues(alpha: 0.45),
                      ),
                    ),
                    // Sharp portrait (left) + details (right).
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: AspectRatio(
                              aspectRatio: 3 / 4,
                              child: StoopAvatar(assetId: card.primaryAssetId),
                            ),
                          ),
                          const SizedBox(width: 18),
                          Expanded(child: _heroDetails(card)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _heroDetails(StoopCard card) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            gradient: stoopGradient(context),
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Text(
            '✦ FEATURED',
            style: TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          card.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 26,
            fontWeight: FontWeight.bold,
          ),
        ),
        if (card.summary.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            stoopResolveMacros(card.summary, card.name),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.85)),
          ),
        ],
        const SizedBox(height: 8),
        Row(
          children: [
            Icon(
              Icons.arrow_upward_rounded,
              size: 14,
              color: stoopAccent(context),
            ),
            const SizedBox(width: 2),
            Text(
              '${card.score}',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 14),
            if (card.creator != null)
              Flexible(
                child: Text(
                  '@${card.creator!.displayName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
                ),
              ),
          ],
        ),
      ],
    );
  }

  SliverToBoxAdapter _carousel(String title, List<StoopCard> cards) {
    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary(context),
              ),
            ),
          ),
          SizedBox(
            height: 200,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: cards.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (_, i) => SizedBox(
                width: 140,
                child: StoopCardTile(
                  card: cards[i],
                  onTap: () => _openCard(cards[i]),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  SliverPadding _gridSliver() {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 168,
          childAspectRatio: 0.66,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        delegate: SliverChildBuilderDelegate(
          (_, i) =>
              StoopCardTile(card: _grid[i], onTap: () => _openCard(_grid[i])),
          childCount: _grid.length,
        ),
      ),
    );
  }

  Widget _centered(IconData icon, String text, {bool retry = false}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: AppColors.iconSecondary(context)),
            const SizedBox(height: 12),
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textTertiary(context)),
            ),
            if (retry) ...[
              const SizedBox(height: 14),
              OutlinedButton(onPressed: _loadAll, child: const Text('Retry')),
            ],
          ],
        ),
      ),
    );
  }
}
