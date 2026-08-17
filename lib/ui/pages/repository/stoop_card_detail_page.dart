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
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/providers/auth_state.dart';
import 'package:front_porch_ai/services/backporch/backporch.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/group_card_importer.dart';
import 'package:front_porch_ai/ui/pages/repository/stoop_avatar.dart';
import 'package:front_porch_ai/ui/pages/repository/stoop_card_comments.dart';
import 'package:front_porch_ai/ui/pages/repository/stoop_card_sections.dart';
import 'package:front_porch_ai/ui/pages/repository/stoop_collapsible.dart';
import 'package:front_porch_ai/ui/pages/repository/stoop_group_sections.dart';
import 'package:front_porch_ai/ui/pages/repository/stoop_creator_page.dart';
import 'package:front_porch_ai/ui/pages/repository/stoop_glass.dart';
import 'package:front_porch_ai/ui/pages/repository/stoop_report.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Open a character as a frosted glass panel that slides in from the right while
/// the browse grid stays visible (dimmed) behind it. Tap the scrim to dismiss.
///
/// `showGeneralDialog` renders in the root overlay, which sits *above* the
/// `MaterialApp.builder` that applies the app's responsive text scaler — so we
/// capture the launching context's `textScaler` and re-apply it inside, or the
/// panel renders text at full (much larger) scale. The `Material` wrapper gives
/// the panel's InkWell/IconButtons the Material ancestor they require (without
/// it they throw and paint as red error boxes).
Future<void> showStoopDetail(BuildContext context, String cardId) {
  final appScaler = MediaQuery.textScalerOf(context);
  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Character',
    barrierColor: Colors.black.withValues(alpha: 0.5),
    transitionDuration: const Duration(milliseconds: 280),
    pageBuilder: (ctx, _, _) {
      // Roughly half the window, but never narrower than the old fixed panel.
      final panelWidth = (MediaQuery.sizeOf(ctx).width * 0.5).clamp(
        460.0,
        1200.0,
      );
      return MediaQuery(
        data: MediaQuery.of(ctx).copyWith(textScaler: appScaler),
        child: Align(
          alignment: Alignment.centerRight,
          child: SizedBox(
            width: panelWidth,
            height: double.infinity,
            child: Material(
              type: MaterialType.transparency,
              child: _StoopDetailPanel(cardId: cardId),
            ),
          ),
        ),
      );
    },
    transitionBuilder: (_, anim, _, child) => SlideTransition(
      position: Tween(
        begin: const Offset(1, 0),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
      child: child,
    ),
  );
}

class _StoopDetailPanel extends StatefulWidget {
  final String cardId;
  const _StoopDetailPanel({required this.cardId});

  @override
  State<_StoopDetailPanel> createState() => _StoopDetailPanelState();
}

class _StoopDetailPanelState extends State<_StoopDetailPanel> {
  final _api = BackporchApi();
  // Mock-only this pass — never the live Backporch comments API.
  final _commentsClient = MemoryStoopCommentsClient(
    optIn: StoopCommentsOptIn.instance,
  );
  StoopCardDetail? _detail;
  bool _loading = true;
  String? _error;
  int _score = 0;
  int _downloadCount = 0;
  int _myVote = 0;
  int _greetingIndex = 0;
  int _memberIndex = 0; // which group member the carousel is showing
  bool _downloading = false;
  StreamSubscription<StoopCardStats>? _statsSub;

  @override
  void initState() {
    super.initState();
    // Live counters while the panel is open. The server's numbers are
    // authoritative — our own vote's broadcast carries the same score as its
    // HTTP reply, so accepting every push is safe.
    _statsSub = StoopMessageSocket.onCardStats.listen((s) {
      if (s.cardId != widget.cardId || !mounted) return;
      setState(() {
        _score = s.score;
        _downloadCount = s.downloadCount;
      });
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
      final d = await _api.cardDetail(_token, widget.cardId);
      if (!mounted) return;
      _commentsClient.setCardCommentsEnabled(d.id, d.commentsEnabled);
      setState(() {
        _detail = d;
        _score = d.score;
        _downloadCount = d.downloadCount;
        _myVote = d.myVote;
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Couldn’t load this character.';
          _loading = false;
        });
      }
    }
  }

  Future<void> _vote(int value) async {
    final next = _myVote == value ? 0 : value;
    final prevScore = _score;
    final prevVote = _myVote;
    setState(() {
      _score += next - _myVote;
      _myVote = next;
    });
    try {
      final r = await _api.vote(_token, widget.cardId, next);
      if (mounted) {
        setState(() {
          _score = r.score;
          _myVote = r.myVote;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _score = prevScore;
          _myVote = prevVote;
        });
      }
    }
  }

  Future<void> _download() async {
    final d = _detail;
    if (d == null) return;
    setState(() => _downloading = true);
    final messenger = ScaffoldMessenger.of(context);
    final repo = context.read<CharacterRepository>();
    // For a group card, import via the shared GroupCardImporter (providers read
    // before the await to avoid using context across an async gap).
    final groupImporter = d.type == 'GROUP'
        ? GroupCardImporter(
            context.read<GroupChatRepository>(),
            context.read<StorageService>(),
            liveDatabase(context),
          )
        : null;
    // World cards import as places; provider read before the await, like above.
    final worldRepo = d.isWorld ? context.read<WorldRepository>() : null;
    Directory? tmp;
    try {
      final payload = await _api.download(_token, widget.cardId);
      // Newer servers return the fresh count; covers a briefly-dropped socket.
      final freshCount = (payload['downloadCount'] as num?)?.toInt();
      if (freshCount != null && mounted) {
        setState(() => _downloadCount = freshCount);
      }
      final cardJson = payload['card'] as Map<String, dynamic>?;
      if (cardJson == null) throw Exception('no card data');
      if (worldRepo != null) {
        // WORLD card: the payload IS the .fpworld envelope — import it whole
        // (lore + climate + traits + cover) as a new place.
        final imported = await worldRepo.importWorldJson(cardJson);
        messenger.showSnackBar(
          SnackBar(content: Text('“${imported.name}” added to your places.')),
        );
        return;
      }
      if (groupImporter != null) {
        final result = await groupImporter.importCard(
          GroupCard.fromJson(cardJson),
        );
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              result.created
                  ? '“${result.groupName}” added to your groups.'
                  : 'Couldn’t add that group — it had no usable members.',
            ),
          ),
        );
        return;
      }
      tmp = await Directory.systemTemp.createTemp('stoop_dl');
      final jsonPath = p.join(tmp.path, 'card.json');
      await File(jsonPath).writeAsString(jsonEncode(cardJson));
      final v2 = V2CardService();
      final card = await v2.readCardFromJsonFile(jsonPath);
      if (card == null) throw Exception('parse failed');
      String? avatarPath;
      final assetId = payload['primaryAssetId'] as String?;
      if (assetId != null) {
        final bytes = await _api.assetBytes(_token, assetId);
        avatarPath = p.join(tmp.path, 'avatar.png');
        await File(avatarPath).writeAsBytes(bytes);
      }
      final pngPath = p.join(tmp.path, 'card.png');
      await v2.saveCardAsPng(card, pngPath, avatarPath);
      await repo.importCharacter(File(pngPath));
      messenger.showSnackBar(
        SnackBar(content: Text('“${d.name}” added to your library.')),
      );
    } catch (_) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            d.isWorld
                ? 'Couldn’t download that place.'
                : 'Couldn’t download that character.',
          ),
        ),
      );
    } finally {
      await tmp?.delete(recursive: true).catchError((_) => tmp!);
      if (mounted) setState(() => _downloading = false);
    }
  }

  Future<void> _report() async {
    if (!stoopCanReport(context.read<AuthState>().user)) return;
    final messenger = ScaffoldMessenger.of(context);
    final result = await showDialog<({String category, String reason})>(
      context: context,
      builder: (_) => const StoopReportDialog(),
    );
    if (result == null) return;
    try {
      await _api.reportCharacter(
        _token,
        widget.cardId,
        category: result.category,
        reason: result.reason,
      );
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Reported. Thanks — a moderator will review it.'),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(stoopReportFailureMessage(e))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    const radius = BorderRadius.only(
      topLeft: Radius.circular(22),
      bottomLeft: Radius.circular(22),
    );
    return ClipRRect(
      borderRadius: radius,
      child: Container(
        decoration: BoxDecoration(
          color: stoopBg0(context),
          borderRadius: radius,
          border: Border(
            left: BorderSide(
              color: AppColors.stoopAmber.withValues(alpha: 0.35),
            ),
          ),
        ),
        // Transparent Material so the expander ListTiles inside paint their
        // ink splashes ON this panel rather than on the Material behind the
        // colored box (where they were invisible — debug builds assert).
        child: Material(
          type: MaterialType.transparency,
          child: _loading
              ? const StoopLamp()
              : _error != null || _detail == null
              ? stoopEmpty(context, glyph: '🌙', title: _error ?? 'Not found')
              : _content(_detail!),
        ),
      ),
    );
  }

  // The name {{char}} actually maps to in chat — the CARD's own name, which
  // may differ from the post's display title ("Misty" vs "Misty Meadows,
  // Misguided Meteorologist"). Previews must read like the chat will.
  String _chatName(StoopCardDetail d) {
    final n = (d.card['name'] ?? '').toString().trim();
    return n.isNotEmpty ? n : d.name;
  }

  String _s(StoopCardDetail d, String key) =>
      stoopResolveMacros((d.card[key] ?? '').toString(), _chatName(d));

  List<String> _greetings(StoopCardDetail d) {
    final first = _s(d, 'first_mes');
    // `is List`, never `as List?`: this card came off the wire from a
    // stranger's upload, and the `as` form THROWS on a present-but-wrong-typed
    // value, taking down the whole detail panel instead of omitting one
    // section (same rule as stoop_identity_sections.dart).
    final raw = d.card['alternate_greetings'];
    final alts = (raw is List ? raw : const [])
        .map((e) => stoopResolveMacros(e.toString(), d.name))
        .where((s) => s.isNotEmpty)
        .toList();
    return [if (first.isNotEmpty) first, ...alts];
  }

  Widget _content(StoopCardDetail d) {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: _hero(d)),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 36),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              _actions(d),
              const SizedBox(height: 10),
              _reportButton(),
              if (d.tags.isNotEmpty) ...[
                const SizedBox(height: 16),
                // Teal tag pills (hub .hub-tag).
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    for (final t in d.tags)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 11,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: stoopTealSoft(context),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: AppColors.stoopTeal.withValues(alpha: 0.35),
                          ),
                        ),
                        child: Text(
                          '#$t',
                          style: TextStyle(
                            color: stoopTealText(context),
                            fontSize: 12.5,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
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

  // Cinematic header: the avatar fills the top with a scrim carrying the name,
  // @creator, and stats. Close + report float over it.
  Widget _hero(StoopCardDetail d) {
    return SizedBox(
      height: 260,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Blurred, darkened fill of the same art — so a tall portrait or a
          // tight headshot never has to crop the face to fill this wide, short
          // banner. The sharp portrait sits on top, shown whole.
          //
          // Blur the IMAGE itself (ImageFiltered), not the backdrop: this panel
          // is already a frosted BackdropFilter, and nesting a second
          // BackdropFilter here breaks compositing (the content below the hero
          // wouldn't paint until scrolled).
          ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
            child: Transform.scale(
              scale: 1.18,
              child: StoopAvatar(assetId: d.primaryAssetId),
            ),
          ),
          // Dusk-toned scrims (hub #0a0805 tints) — the hero stays a night
          // scene in both themes, so overlay text uses the const dusk ramp.
          Container(color: const Color(0x4D0A0805)),
          Center(
            child: StoopAvatar(assetId: d.primaryAssetId, fit: BoxFit.contain),
          ),
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x400A0805),
                  Colors.transparent,
                  Color(0xD90A0805),
                ],
                stops: [0, 0.4, 1],
              ),
            ),
          ),
          Positioned(
            top: 10,
            right: 10,
            child: _glassIcon(Icons.close, () => Navigator.of(context).pop()),
          ),
          Positioned(
            left: 18,
            right: 18,
            bottom: 14,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  d.name,
                  style: stoopDisplay(
                    context,
                    size: 26,
                    color: AppColors.stoopCream,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (d.creator != null)
                      GestureDetector(
                        onTap: () {
                          Navigator.of(context).pop();
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  StoopCreatorPage(creatorId: d.creator!.id),
                            ),
                          );
                        },
                        child: Text(
                          '@${d.creator!.displayName}',
                          style: const TextStyle(
                            color: AppColors.stoopTealText,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    // Attribution: uploader ≠ author ("@handle · created by X").
                    if (d.originalCreator != null)
                      Flexible(
                        child: Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: Text(
                            '${d.creator != null ? '· ' : ''}created by '
                            '${d.originalCreator}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.85),
                              fontStyle: FontStyle.italic,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(width: 12),
                    Icon(
                      Icons.download_rounded,
                      size: 14,
                      color: Colors.white.withValues(alpha: 0.8),
                    ),
                    const SizedBox(width: 3),
                    Text(
                      '$_downloadCount',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                      ),
                    ),
                    if (stoopTokenLabel(d.tokenCount) case final tl?) ...[
                      const SizedBox(width: 12),
                      Icon(
                        Icons.data_usage_rounded,
                        size: 13,
                        color: Colors.white.withValues(alpha: 0.8),
                      ),
                      const SizedBox(width: 3),
                      Text(
                        '~$tl tokens',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                    // Version pill — only once the card has been updated (v2+),
                    // so it reads as "this was updated" rather than noise on v1.
                    if (d.version >= 2) ...[
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.autorenew_rounded,
                              size: 12,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              'v${d.version}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (d.nsfw) ...[
                      const SizedBox(width: 12),
                      const StoopBadge(StoopBadgeKind.nsfw),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Ember report control. Unverified accounts never get the dialog — they
  // see “Confirm email to report” (hub parity, 2026-08).
  Widget _reportButton() {
    return StoopReportControl(
      user: context.watch<AuthState>().user,
      onReport: _report,
    );
  }

  // Floating close control over the hero (always on the dark scrim).
  Widget _glassIcon(IconData icon, VoidCallback onTap) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xBF14110D),
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.stoopBorderHi),
      ),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, size: 18, color: AppColors.stoopCream2),
        ),
      ),
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
                      ? () => setState(() => _greetingIndex = idx - 1)
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
                      ? () => setState(() => _greetingIndex = idx + 1)
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

  // Group card body: the group's own overview up top (scenario, greeting,
  // pre-seeded dynamics, group lorebook, system prompt), then a "Members"
  // divider and a 1/N carousel where each member reads like a solo character.
  List<Widget> _groupSections(StoopCardDetail d) {
    // Wrong-typed member lists must degrade to "no members", not throw — see
    // the note in _greetings.
    final rawMembers = d.card['raw_member_data'];
    final plainMembers = d.card['members'];
    final List<dynamic> members = rawMembers is List
        ? rawMembers
        : (plainMembers is List ? plainMembers : const []);
    return [
      ...stoopGroupOverview(context, d.card, d.name),
      if (members.isNotEmpty) ...[
        Padding(
          padding: const EdgeInsets.only(top: 28, bottom: 2),
          child: Row(
            children: [
              Text('Members', style: stoopSectionTitleStyle(context)),
              const SizedBox(width: 12),
              Expanded(child: Divider(color: stoopBorder(context))),
            ],
          ),
        ),
        _memberCarousel(members),
      ],
    ];
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
                      ? () => setState(() => _memberIndex = idx - 1)
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
                      ? () => setState(() => _memberIndex = idx + 1)
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
