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

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/group_card.dart';
import 'package:front_porch_ai/providers/auth_state.dart';
import 'package:front_porch_ai/services/backporch/backporch.dart';
import 'package:front_porch_ai/services/character_repository.dart';
import 'package:front_porch_ai/services/group_card_importer.dart';
import 'package:front_porch_ai/services/group_chat_repository.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/v2_card_service.dart';
import 'package:front_porch_ai/ui/pages/repository/stoop_avatar.dart';
import 'package:front_porch_ai/ui/pages/repository/stoop_card_sections.dart';
import 'package:front_porch_ai/ui/pages/repository/stoop_group_sections.dart';
import 'package:front_porch_ai/ui/pages/repository/stoop_creator_page.dart';
import 'package:front_porch_ai/ui/pages/repository/stoop_glass.dart';
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
      final panelWidth = (MediaQuery.sizeOf(ctx).width * 0.5).clamp(460.0, 1200.0);
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
            context.read<AppDatabase>(),
          )
        : null;
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
        const SnackBar(content: Text('Couldn’t download that character.')),
      );
    } finally {
      await tmp?.delete(recursive: true).catchError((_) => tmp!);
      if (mounted) setState(() => _downloading = false);
    }
  }

  Future<void> _report() async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await showDialog<({String category, String reason})>(
      context: context,
      builder: (_) => const _ReportDialog(),
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
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Couldn’t file that report. Try again.')),
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
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.backgroundOf(context).withValues(alpha: 0.8),
            borderRadius: radius,
            border: Border(
              left: BorderSide(
                color: stoopAccent(context).withValues(alpha: 0.4),
              ),
            ),
          ),
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null || _detail == null
              ? Center(
                  child: Text(
                    _error ?? 'Not found',
                    style: TextStyle(color: AppColors.textTertiary(context)),
                  ),
                )
              : _content(_detail!),
        ),
      ),
    );
  }

  String _s(StoopCardDetail d, String key) =>
      stoopResolveMacros((d.card[key] ?? '').toString(), d.name);

  List<String> _greetings(StoopCardDetail d) {
    final first = _s(d, 'first_mes');
    final alts =
        (d.card['alternate_greetings'] as List?)
            ?.map((e) => stoopResolveMacros(e.toString(), d.name))
            .where((s) => s.isNotEmpty)
            .toList() ??
        const [];
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
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    for (final t in d.tags)
                      Text(
                        '#$t',
                        style: TextStyle(
                          color: AppColors.textTertiary(context),
                        ),
                      ),
                  ],
                ),
              ],
              if (d.type == 'GROUP')
                ..._groupSections(d)
              else
                ...stoopStandardSections(
                  context,
                  d.card,
                  d.name,
                  firstMessage: _firstMessage(d),
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
            child: StoopAvatar(assetId: d.primaryAssetId),
          ),
          Container(color: Colors.black.withValues(alpha: 0.3)),
          Center(
            child: StoopAvatar(
              assetId: d.primaryAssetId,
              fit: BoxFit.contain,
            ),
          ),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.25),
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.85),
                ],
                stops: const [0, 0.4, 1],
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
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
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
                          style: TextStyle(
                            color: stoopAccent(context),
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
                      Text(
                        'NSFW',
                        style: TextStyle(
                          color: AppColors.resolve(
                            context,
                            Colors.pinkAccent,
                            Colors.pink,
                          ),
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
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

  // A red pill so reporting is obvious and easy to find, under the vote row.
  Widget _reportButton() {
    final red = AppColors.resolve(context, Colors.redAccent, Colors.red);
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: _report,
        icon: const Icon(Icons.flag_rounded, size: 18),
        label: const Text('Report Character'),
        style: TextButton.styleFrom(
          foregroundColor: red,
          backgroundColor: red.withValues(alpha: 0.12),
          side: BorderSide(color: red.withValues(alpha: 0.55)),
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        ),
      ),
    );
  }

  Widget _glassIcon(IconData icon, VoidCallback onTap) {
    return StoopPill(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: 18, color: Colors.white),
        ),
      ),
    );
  }

  Widget _actions(StoopCardDetail d) {
    final accent = stoopAccent(context);
    return Row(
      children: [
        Container(
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerOf(context),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_downward_rounded),
                color: _myVote == -1
                    ? Colors.redAccent
                    : AppColors.iconSecondary(context),
                onPressed: () => _vote(-1),
              ),
              Text(
                '$_score',
                style: TextStyle(
                  color: AppColors.textPrimary(context),
                  fontWeight: FontWeight.bold,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.arrow_upward_rounded),
                color: _myVote == 1 ? accent : AppColors.iconSecondary(context),
                onPressed: () => _vote(1),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: 0.4),
                  blurRadius: 18,
                  spreadRadius: -4,
                ),
              ],
            ),
            child: FilledButton.icon(
              onPressed: _downloading ? null : _download,
              icon: _downloading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download_rounded, size: 18),
              label: Text(_downloading ? 'Adding…' : 'Download to library'),
              style: FilledButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: AppColors.background,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ),
      ],
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
                  onPressed: idx > 0
                      ? () => setState(() => _greetingIndex = idx - 1)
                      : null,
                ),
                Text(
                  '${idx + 1}/${greetings.length}',
                  style: TextStyle(color: AppColors.textTertiary(context)),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.chevron_right, size: 20),
                  onPressed: idx < greetings.length - 1
                      ? () => setState(() => _greetingIndex = idx + 1)
                      : null,
                ),
              ],
            ),
          StoopGlass(
            radius: 12,
            padding: const EdgeInsets.all(14),
            child: Text(
              greetings[idx],
              style: TextStyle(
                color: AppColors.textSecondary(context),
                height: 1.5,
              ),
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
    final members =
        (d.card['raw_member_data'] as List?) ??
        (d.card['members'] as List?) ??
        const [];
    return [
      ...stoopGroupOverview(context, d.card, d.name),
      if (members.isNotEmpty) ...[
        Padding(
          padding: const EdgeInsets.only(top: 28, bottom: 2),
          child: Row(
            children: [
              Text('Members', style: stoopSectionTitleStyle(context)),
              const SizedBox(width: 12),
              Expanded(child: Divider(color: AppColors.borderOf(context))),
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
                  onPressed: idx > 0
                      ? () => setState(() => _memberIndex = idx - 1)
                      : null,
                ),
                Text(
                  '${idx + 1}/${members.length}',
                  style: TextStyle(color: AppColors.textTertiary(context)),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.chevron_right, size: 20),
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

/// Report dialog — category + optional reason.
class _ReportDialog extends StatefulWidget {
  const _ReportDialog();

  @override
  State<_ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<_ReportDialog> {
  static const _categories = {
    'ILLEGAL': 'Illegal / involves minors',
    'PROHIBITED_IMAGE': 'Nude / explicit image (not allowed)',
    'MISLABELED': 'Wrong or missing NSFW label',
    'STOLEN': 'Stolen / reuploaded',
    'LOW_EFFORT': 'Low-effort / slop',
    'SPAM': 'Spam or broken',
    'OTHER': 'Something else',
  };
  String _category = 'ILLEGAL';
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.cardOf(context),
      title: Text(
        'Report this card',
        style: TextStyle(color: AppColors.textPrimary(context)),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RadioGroup<String>(
            groupValue: _category,
            onChanged: (v) => setState(() => _category = v ?? _category),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final e in _categories.entries)
                  RadioListTile<String>(
                    value: e.key,
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(
                      e.value,
                      style: TextStyle(color: AppColors.textSecondary(context)),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _reason,
            maxLines: 2,
            style: TextStyle(color: AppColors.textPrimary(context)),
            decoration: InputDecoration(
              hintText: 'Anything else? (optional)',
              hintStyle: TextStyle(color: AppColors.textTertiary(context)),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, (
            category: _category,
            reason: _reason.text.trim(),
          )),
          child: const Text('Submit report'),
        ),
      ],
    );
  }
}
