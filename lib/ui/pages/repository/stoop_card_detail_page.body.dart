// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Detail body: actions, greetings carousel, group member pager.
// Load, vote, download, and the untrusted-JSON list reads stay
// on stoop_card_detail_page.dart.

part of 'stoop_card_detail_page.dart';

extension _StoopDetailPanelBody on _StoopDetailPanelState {
  Widget _content(StoopCardDetail d) {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: StoopDetailTop(
            detail: d,
            downloadCount: _downloadCount,
            onClose: () => Navigator.of(context).pop(),
            onCreatorTap: d.creator == null
                ? null
                : () =>
                      openStoopCreator(context, d.creator!.id, popFirst: true),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 36),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              _actions(d),
              const SizedBox(height: 10),
              _reportButton(),
              const SizedBox(height: 16),
              if (d.type == 'GROUP')
                ..._groupSections(d)
              else if (d.isWorld)
                ...stoopWorldSections(context, d.card)
              else
                ...stoopStandardSections(
                  context,
                  d.card,
                  _chatName(d),
                  firstMessage: _firstMessage(d),
                ),
              const SizedBox(height: 28),
              StoopCardDiscussionSection(
                cardId: d.id,
                cardOwnerId: d.creator?.id,
                user: context.watch<AuthState>().user,
                client: _commentsClient,
                commentsEnabled: d.commentsEnabled,
                commentsLocked: d.commentsLocked,
                persistFlags: ({commentsEnabled, commentsLocked}) {
                  return _api.patchCardComments(
                    _token,
                    d.id,
                    commentsEnabled: commentsEnabled,
                    commentsLocked: commentsLocked,
                  );
                },
              ),
            ]),
          ),
        ),
      ],
    );
  }

  // Hub votebox (joined ▼ score ▲, amber-lit when upvoted, ember when
  // downvoted) + the lamplight download CTA.
  Widget _actions(StoopCardDetail d) {
    return Row(
      children: [
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: stoopBg1(context),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: stoopBorderHi(context)),
          ),
          child: Row(
            children: [
              _voteCell(
                icon: Icons.arrow_downward_rounded,
                on: _myVote == -1,
                gradient: stoopEmberGradient,
                onTap: () => _vote(-1),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  '$_score',
                  style: TextStyle(
                    color: stoopAmberText(context),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              _voteCell(
                icon: Icons.arrow_upward_rounded,
                on: _myVote == 1,
                gradient: stoopAmberGradient,
                onTap: () => _vote(1),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: StoopAmberButton(
            label: _downloading ? 'Adding…' : 'Download to library',
            icon: _downloading ? null : Icons.download_rounded,
            busy: _downloading,
            onPressed: _downloading ? null : _download,
            padding: const EdgeInsets.symmetric(vertical: 13),
          ),
        ),
      ],
    );
  }

  Widget _voteCell({
    required IconData icon,
    required bool on,
    required Gradient gradient,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Ink(
        decoration: BoxDecoration(gradient: on ? gradient : null),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Icon(
          icon,
          size: 19,
          color: on ? AppColors.stoopAmberInk : stoopCream2(context),
        ),
      ),
    );
  }

  Widget _firstMessage(StoopCardDetail d) {
    final greetings = _greetings(d);
    if (greetings.isEmpty) return const SizedBox.shrink();
    final idx = _greetingIndex.clamp(0, greetings.length - 1);
    final multi = greetings.length > 1;
    return StoopCollapsible(
      title: multi ? 'First message (${greetings.length})' : 'First message',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Greeting carousel lives inside the expanded body so a collapsed card
          // stays a single line; expand to browse the alternates.
          if (multi)
            Row(
              children: [
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.chevron_left, size: 20),
                  color: stoopCream2(context),
                  onPressed: idx > 0
                      ? () => rebuildState(() => _greetingIndex = idx - 1)
                      : null,
                ),
                Text(
                  '${idx + 1}/${greetings.length}',
                  style: TextStyle(color: stoopMute(context)),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.chevron_right, size: 20),
                  color: stoopCream2(context),
                  onPressed: idx < greetings.length - 1
                      ? () => rebuildState(() => _greetingIndex = idx + 1)
                      : null,
                ),
              ],
            ),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: stoopBg1(context),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: stoopBorder(context)),
            ),
            child: Text(
              greetings[idx],
              style: TextStyle(color: stoopCream2(context), height: 1.5),
            ),
          ),
        ],
      ),
    );
  }

  // A 1/N pager over group members; each member's full collapsible field set is
  // rendered with the same builder the solo view uses.
  Widget _memberCarousel(List<dynamic> members) {
    final idx = _memberIndex.clamp(0, members.length - 1);
    final rawEntry = members[idx];
    final m = rawEntry is Map
        ? Map<String, dynamic>.from(
            (rawEntry['data'] is Map ? rawEntry['data'] : rawEntry) as Map,
          )
        : <String, dynamic>{};
    final name = (m['name'] ?? 'Member').toString();
    return Padding(
      padding: const EdgeInsets.only(top: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  name,
                  style: stoopSectionTitleStyle(context),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (members.length > 1) ...[
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.chevron_left, size: 20),
                  color: stoopCream2(context),
                  onPressed: idx > 0
                      ? () => rebuildState(() => _memberIndex = idx - 1)
                      : null,
                ),
                Text(
                  '${idx + 1}/${members.length}',
                  style: TextStyle(color: stoopMute(context)),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.chevron_right, size: 20),
                  color: stoopCream2(context),
                  onPressed: idx < members.length - 1
                      ? () => rebuildState(() => _memberIndex = idx + 1)
                      : null,
                ),
              ],
            ],
          ),
          ...stoopStandardSections(context, m, name),
        ],
      ),
    );
  }
}
