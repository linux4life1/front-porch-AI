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

part 'stoop_browse_view.grid.dart';

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

  // Last NSFW preference we loaded for. Flipping AuthState.nsfwEnabled
  // (the account-sheet checkbox) must refetch — the grid stays mounted
  // under the sheet, so leaving The Stoop was the only refresh.
  bool? _nsfwEnabled;
  bool _sawNsfwPref = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _statsSub = StoopMessageSocket.onCardStats.listen(_applyCardStats);
    _loadAll();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nsfw = context.watch<AuthState>().user?.nsfwEnabled;
    if (_nsfwEnabled == nsfw) return;
    final first = !_sawNsfwPref;
    _sawNsfwPref = true;
    _nsfwEnabled = nsfw;
    if (!first) _loadAll();
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
}
