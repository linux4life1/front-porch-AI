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
import 'package:front_porch_ai/ui/pages/repository/stoop_verified_badge.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// The community browse experience, in the hub's porch-at-dusk dress:
/// Mod's Picks (hero + pick row), a Following row, a Groups row, and the main
/// grid with smart search (`@creator`, `#tag`, or a name), a sort menu, and
/// chip type filters.
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
  // Bumped by every full (re)load. A response that comes back carrying an
  // older generation belongs to a filter/sort the user has already replaced,
  // so it must never land in the grid.
  int _reqGen = 0;
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
    final gen = ++_reqGen;
    // Worlds are announced but not queryable until the backend accepts the
    // WORLD type — show the coming-soon panel without hitting the server.
    if (_type == 'world' && !kStoopWorldsLive) {
      setState(() {
        _grid.clear();
        _picks = const [];
        _following = const [];
        _groups = const [];
        _hasMore = false;
        _loading = false;
        _error = null;
      });
      return;
    }
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
      if (!mounted || gen != _reqGen) return;
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
      if (mounted && gen == _reqGen) {
        setState(() {
          _error = 'Couldn’t load The Stoop. Pull to retry.';
          _loading = false;
        });
      }
    }
  }

  Future<void> _loadMore() async {
    final token = _token;
    if (token == null || _loading || _loadingMore || !_hasMore) return;
    final gen = _reqGen;
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
      if (gen != _reqGen) {
        // A newer filter/sort replaced the list while this page was in
        // flight: appending it would mix the old filter's cards into the new
        // grid and push _page past a page nobody fetched. Drop the items, but
        // still clear the flag or pagination stays wedged.
        setState(() => _loadingMore = false);
        return;
      }
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
    return ColoredBox(
      color: stoopBg0(context),
      child: Column(
        children: [
          _searchBar(),
          Expanded(child: _content()),
        ],
      ),
    );
  }

  Widget _content() {
    if (_type == 'world' && !kStoopWorldsLive) {
      // Keep the header (sort/type filters) so the panel isn't a dead end.
      return CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _browseHeader()),
          SliverFillRemaining(
            hasScrollBody: false,
            child: stoopEmpty(
              context,
              glyph: '🏞️',
              title: 'Worlds are coming soon to The Stoop',
              body:
                  'Soon you’ll be able to share and download portable places '
                  '(.fpworld) — cover art, lore, climate, and traits included '
                  '— moderated just like characters.',
            ),
          ),
        ],
      );
    }
    if (_loading) return const StoopLamp(caption: 'Lighting the porch…');
    if (_error != null) {
      return stoopEmpty(
        context,
        glyph: '🌙',
        title: 'Couldn’t load The Stoop',
        body: 'Check your connection and try again.',
        action: OutlinedButton(
          onPressed: _loadAll,
          style: OutlinedButton.styleFrom(
            foregroundColor: stoopCream2(context),
            side: BorderSide(color: stoopBorderHi(context)),
          ),
          child: const Text('Retry'),
        ),
      );
    }
    final featured = _query.isEmpty && _picks.isNotEmpty ? _picks.first : null;
    return RefreshIndicator(
      color: AppColors.stoopAmber,
      onRefresh: _loadAll,
      child: CustomScrollView(
        controller: _scroll,
        slivers: [
          if (featured != null) ...[
            SliverToBoxAdapter(
              child: _sectionHead('⭐', 'MOD’S PICKS', topPad: 6),
            ),
            _heroSliver(featured),
            if (_picks.length > 1) _pickRow(_picks.skip(1).toList()),
          ],
          if (_following.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: _sectionHead('🪑', 'FROM CREATORS YOU FOLLOW'),
            ),
            _pickRow(_following),
          ],
          if (_groups.isNotEmpty) ...[
            SliverToBoxAdapter(child: _sectionHead('👥', 'GROUPS')),
            _pickRow(_groups),
          ],
          SliverToBoxAdapter(child: _browseHeader()),
          if (_grid.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: stoopEmpty(
                context,
                glyph: '🏮',
                title: 'Nothing on the porch',
                body: _query.isEmpty
                    ? 'No cards here yet — check back soon.'
                    : 'No cards match “$_query”.',
              ),
            )
          else
            _gridSliver(),
          if (_loadingMore)
            const SliverToBoxAdapter(
              child: Padding(padding: EdgeInsets.all(20), child: StoopLamp()),
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
        style: TextStyle(color: stoopCream(context)),
        decoration: stoopInput(
          context,
          'Search name, @creator, or #tag',
          prefixIcon: Icon(Icons.search, color: stoopMute(context)),
          suffixIcon: _query.isEmpty
              ? null
              : IconButton(
                  icon: Icon(Icons.close, color: stoopMute(context)),
                  onPressed: () {
                    _search.clear();
                    _applySearch('');
                  },
                ),
        ),
      ),
    );
  }

  // The hub's uppercase amber eyebrow (.hub-pick-eyebrow) heading a section.
  Widget _sectionHead(String glyph, String label, {double topPad = 18}) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, topPad, 16, 10),
      child: Row(
        children: [
          Text(glyph, style: const TextStyle(fontSize: 13)),
          const SizedBox(width: 7),
          Text(
            label,
            style: TextStyle(
              color: stoopAmberText(context),
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _browseHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 10,
        runSpacing: 8,
        children: [
          Text(
            _query.isEmpty ? 'Browse all' : 'Results',
            style: stoopDisplay(context, size: 19),
          ),
          const SizedBox(width: 2),
          _typeChips(),
          _sortMenu(),
        ],
      ),
    );
  }

  Widget _sortMenu() {
    const labels = {'newest': 'Newest', 'top': 'Top', 'downloads': 'Downloads'};
    return PopupMenuButton<String>(
      initialValue: _sort,
      color: stoopCard2(context),
      onSelected: (v) {
        setState(() => _sort = v);
        _loadAll();
      },
      itemBuilder: (_) => labels.entries
          .map(
            (e) => PopupMenuItem(
              value: e.key,
              child: Text(
                e.value,
                style: TextStyle(color: stoopCream2(context)),
              ),
            ),
          )
          .toList(),
      child: Container(
        padding: const EdgeInsets.fromLTRB(13, 7, 8, 7),
        decoration: BoxDecoration(
          color: stoopBg1(context),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: stoopBorderHi(context)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              labels[_sort]!,
              style: TextStyle(color: stoopCream2(context), fontSize: 13),
            ),
            Icon(Icons.arrow_drop_down, color: stoopMute(context), size: 20),
          ],
        ),
      ),
    );
  }

  // Hub filter chips (.hub-chip): quiet pills; the active one lights up on the
  // amber gradient with dark ink.
  Widget _typeChips() {
    const types = [
      ('all', 'All'),
      ('solo', 'Singles'),
      ('group', 'Groups'),
      ('world', 'Worlds'),
    ];
    return Wrap(
      spacing: 6,
      children: [
        for (final (value, label) in types)
          _chip(label, _type == value, () {
            setState(() => _type = value);
            _loadAll();
          }),
      ],
    );
  }

  Widget _chip(String label, bool on, VoidCallback onTap) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          gradient: on ? stoopAmberGradient : null,
          color: on ? null : stoopBg1(context),
          borderRadius: BorderRadius.circular(999),
          border: on ? null : Border.all(color: stoopBorderHi(context)),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: on ? AppColors.stoopAmberInk : stoopCream2(context),
            fontSize: 13,
            fontWeight: on ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  // The Mod's-Pick hero (.hub-pickhero): a blurred, zoomed fill of the card
  // art behind a dusk scrim, with the SHARP portrait at true 3:4 on the left
  // so faces never stretch, and name/summary/CTA beside it.
  SliverToBoxAdapter _heroSliver(StoopCard card) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
        child: GestureDetector(
          onTap: () => _openCard(card),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: Container(
              height: 230,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: AppColors.stoopAmber.withValues(alpha: 0.3),
                ),
                boxShadow: [
                  const BoxShadow(
                    color: Color(0x59000000),
                    blurRadius: 30,
                    offset: Offset(0, 10),
                  ),
                  BoxShadow(
                    color: AppColors.stoopAmber.withValues(alpha: 0.06),
                    blurRadius: 44,
                  ),
                ],
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Blur the image itself (not a backdrop) and oversize it so
                  // the blur's transparent edge never shows.
                  ImageFiltered(
                    imageFilter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
                    child: Transform.scale(
                      scale: 1.18,
                      child: StoopAvatar(assetId: card.primaryAssetId),
                    ),
                  ),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [Color(0x590A0805), Color(0xB80A0805)],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        Container(
                          clipBehavior: Clip.antiAlias,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(9),
                            border: Border.all(color: AppColors.stoopBorderHi),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x66000000),
                                blurRadius: 24,
                                offset: Offset(0, 8),
                              ),
                            ],
                          ),
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
    );
  }

  // Hero text column. The hero sits on a dark scrim in BOTH themes, so this
  // deliberately uses the dusk constants rather than theme-resolved tokens.
  Widget _heroDetails(StoopCard card) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            const StoopBadge(StoopBadgeKind.featured),
            if (card.isGroup) const StoopBadge(StoopBadgeKind.group),
            if (card.isWorld)
              ...stoopWorldKindBadges(
                climateEnabled: stoopCardClimateEnabled(card),
              ),
            if (card.nsfw) const StoopBadge(StoopBadgeKind.nsfw),
          ],
        ),
        const SizedBox(height: 9),
        Text(
          card.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: stoopDisplay(context, size: 26, color: AppColors.stoopCream),
        ),
        if (card.creator != null) ...[
          const SizedBox(height: 3),
          Row(
            children: [
              Flexible(
                child: Text(
                  '@${card.creator!.displayName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.stoopCream2,
                    fontSize: 12.5,
                  ),
                ),
              ),
              StoopVerifiedBadge(
                verification: card.creator!.verification,
                size: 13,
              ),
            ],
          ),
        ],
        if (card.summary.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            stoopResolveMacros(card.summary, card.name),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppColors.stoopCream2, height: 1.45),
          ),
        ],
        const SizedBox(height: 12),
        Row(
          children: [
            StoopAmberButton(
              label: 'View card',
              onPressed: () => _openCard(card),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            ),
            const SizedBox(width: 14),
            Text(
              '▲ ${card.score}   ⬇ ${card.downloadCount}',
              style: const TextStyle(
                color: AppColors.stoopCream2,
                fontSize: 12.5,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // A horizontally-scrolling row of compact tiles (.hub-pickrow).
  SliverToBoxAdapter _pickRow(List<StoopCard> cards) {
    return SliverToBoxAdapter(
      child: SizedBox(
        height: 210,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
          itemCount: cards.length,
          separatorBuilder: (_, _) => const SizedBox(width: 12),
          itemBuilder: (_, i) => SizedBox(
            width: 156,
            child: StoopCardTile(
              card: cards[i],
              compact: true,
              onTap: () => _openCard(cards[i]),
            ),
          ),
        ),
      ),
    );
  }

  SliverPadding _gridSliver() {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 230,
          childAspectRatio: 0.64,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
        ),
        delegate: SliverChildBuilderDelegate(
          (_, i) =>
              StoopCardTile(card: _grid[i], onTap: () => _openCard(_grid[i])),
          childCount: _grid.length,
        ),
      ),
    );
  }
}
