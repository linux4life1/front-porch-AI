// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Browse grid: featured hero, pick rows, and the card sliver.
// Search, sort, type chips, and _loadAll/_loadMore stay on the view
// (async_ui_teardown_guards reads those from the shell file).

part of 'stoop_browse_view.dart';

extension _StoopBrowseViewGrid on _StoopBrowseViewState {
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
          childAspectRatio: kStoopCardTileAspectRatio,
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
