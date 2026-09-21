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

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/providers/auth_state.dart';
import 'package:front_porch_ai/services/backporch/backporch.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/group_card_importer.dart';
import 'package:front_porch_ai/ui/pages/repository/stoop_card_comments.dart';
import 'package:front_porch_ai/ui/pages/repository/stoop_detail_top.dart';
import 'package:front_porch_ai/ui/pages/repository/stoop_card_sections.dart';
import 'package:front_porch_ai/ui/pages/repository/stoop_collapsible.dart';
import 'package:front_porch_ai/ui/pages/repository/stoop_group_sections.dart';
import 'package:front_porch_ai/ui/pages/repository/stoop_glass.dart';
import 'package:front_porch_ai/ui/pages/repository/stoop_nav.dart';
import 'package:front_porch_ai/ui/pages/repository/stoop_report.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

part 'stoop_card_detail_page.body.dart';

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
  late final HttpStoopCommentsClient _commentsClient = HttpStoopCommentsClient(
    _api,
    () => _token,
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

  void rebuildState(VoidCallback fn) => setState(fn);

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

  // Ember report control. Unverified accounts never get the dialog — they
  // see “Confirm email to report” (hub parity, 2026-08).
  Widget _reportButton() {
    return StoopReportControl(
      user: context.watch<AuthState>().user,
      onReport: _report,
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
}
