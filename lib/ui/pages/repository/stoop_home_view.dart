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

import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/models/group_chat.dart';
import 'package:front_porch_ai/providers/auth_state.dart';
import 'package:front_porch_ai/services/backporch/backporch.dart';
import 'package:front_porch_ai/services/character_repository.dart';
import 'package:front_porch_ai/services/group_chat_repository.dart';
import 'package:front_porch_ai/ui/pages/edit_character_page.dart';
import 'package:front_porch_ai/ui/pages/edit_group_page.dart';
import 'package:front_porch_ai/ui/pages/repository/stoop_card_detail_page.dart';
import 'package:front_porch_ai/ui/pages/repository/stoop_card_tile.dart';
import 'package:front_porch_ai/ui/pages/repository/stoop_upload_page.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// The signed-in landing for The Stoop: share a character and track your own
/// uploads through moderation. The community browse grid is a later phase; this
/// is the creator-facing surface.
class StoopHomeView extends StatefulWidget {
  const StoopHomeView({super.key});

  @override
  State<StoopHomeView> createState() => _StoopHomeViewState();
}

class _StoopHomeViewState extends State<StoopHomeView> {
  final _api = BackporchApi();
  bool _loading = true;
  String? _error;
  List<StoopCharacter> _mine = const [];
  List<StoopCard> _downloads = const [];
  StreamSubscription<StoopCardStats>? _statsSub;

  @override
  void initState() {
    super.initState();
    // Live vote/download counters on the download-history tiles.
    _statsSub = StoopMessageSocket.onCardStats.listen((s) {
      if (s.applyTo(_downloads) && mounted) setState(() {});
    });
    _load();
  }

  @override
  void dispose() {
    _statsSub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final token = context.read<AuthState>().accessToken;
    if (token == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await _api.myCharacters(token);
      List<StoopCard> downloads = const [];
      try {
        downloads = await _api.myDownloads(token);
      } catch (_) {
        // download history is non-critical; uploads still render
      }
      if (mounted) {
        setState(() {
          _mine = items;
          _downloads = downloads;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Couldn’t load your uploads. Pull to retry.';
          _loading = false;
        });
      }
    }
  }

  Future<void> _startUpload() async {
    final shared = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => const StoopUploadPage()));
    if (shared == true && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Submitted for review.')));
      _load();
    }
  }

  // Publish a new version of an already-shared character IN PLACE. Finds the
  // local library card this post came from (by the card's stable id, else by
  // name) and opens the wizard locked to it in update mode.
  Future<void> _startUpdate(StoopCharacter c) async {
    final repo = context.read<CharacterRepository>();
    CharacterCard? match;
    final sid = c.originStableId;
    if (sid != null && sid.isNotEmpty) {
      for (final card in repo.characters) {
        if (card.frontPorchExtensions?.stableId == sid) {
          match = card;
          break;
        }
      }
    }
    if (match == null) {
      final wanted = c.name.trim().toLowerCase();
      for (final card in repo.characters) {
        if (card.imagePath != null &&
            card.name.trim().toLowerCase() == wanted) {
          match = card;
          break;
        }
      }
    }
    if (match == null || match.imagePath == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Couldn’t find “${c.name}” in your library to update — '
              'it may have been renamed or removed.',
            ),
          ),
        );
      }
      return;
    }
    final libCard = match;
    // 1) Full character editor (Save → "Next"). Saves to the library first, so
    //    there's one canonical character, then returns the freshly-saved card.
    final saved = await Navigator.of(context).push<CharacterCard>(
      MaterialPageRoute(
        builder: (_) => EditCharacterPage(
          character: libCard,
          saveLabel: 'Next',
          popWithCardOnSave: true,
        ),
      ),
    );
    if (saved == null || !mounted) return; // backed out without saving
    // 2) Stoop publish step (summary/tags/NSFW/standards → new version in place).
    final updated = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => StoopUploadPage(
          updateCharacter: saved,
          updateStoopId: c.id,
          initialNsfw: c.nsfw,
          initialOriginalCreator: c.originalCreator,
        ),
      ),
    );
    if (updated == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Update submitted for review.')),
      );
      _load();
    }
  }

  // Publish a new version of an already-shared GROUP in place. Finds the local
  // group this post came from (by the portable group stable id, else by name),
  // opens the full group editor (Save → "Next", which saves locally + returns
  // the group), then the Stoop publish step re-publishes the same post.
  Future<void> _startGroupUpdate(StoopCharacter c) async {
    final repo = context.read<GroupChatRepository>();
    GroupChat? match;
    final sid = c.originStableId;
    if (sid != null && sid.isNotEmpty) {
      for (final g in repo.groups) {
        if (g.stableId == sid) {
          match = g;
          break;
        }
      }
    }
    if (match == null) {
      final wanted = c.name.trim().toLowerCase();
      for (final g in repo.groups) {
        if (g.name.trim().toLowerCase() == wanted) {
          match = g;
          break;
        }
      }
    }
    if (match == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Couldn’t find “${c.name}” in your groups to update — '
              'it may have been renamed or removed.',
            ),
          ),
        );
      }
      return;
    }
    // 1) Full group editor (Save → "Next"). Saves the local group first (so the
    //    edits — including the new Realism & Dynamics tab — are the source of
    //    truth), then returns the freshly-saved group.
    final saved = await Navigator.of(context).push<GroupChat>(
      MaterialPageRoute(
        builder: (_) => EditGroupPage(
          group: match!,
          saveLabel: 'Next',
          popWithGroupOnSave: true,
        ),
      ),
    );
    if (saved == null || !mounted) return; // backed out without saving
    // 2) Stoop publish step (summary/tags/NSFW/standards → new version in place).
    final updated = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => StoopUploadPage(
          updateGroup: saved,
          updateStoopId: c.id,
          initialNsfw: c.nsfw,
          initialOriginalCreator: c.originalCreator,
        ),
      ),
    );
    if (updated == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Update submitted for review.')),
      );
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Row(
                children: [
                  Text(
                    'Your characters',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary(context),
                    ),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: _startUpload,
                    icon: const Icon(Icons.upload_outlined, size: 18),
                    label: const Text('Share a character'),
                  ),
                ],
              ),
            ),
            Expanded(child: _body()),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return _hint(Icons.cloud_off_outlined, _error!, retry: true);
    }
    if (_mine.isEmpty && _downloads.isEmpty) {
      return _hint(
        Icons.ios_share_outlined,
        'You haven’t shared any characters yet.\nTap “Share a character” to '
        'submit one for review.',
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          if (_mine.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'You haven’t shared any characters yet.',
                style: TextStyle(color: AppColors.textTertiary(context)),
              ),
            )
          else
            for (final c in _mine)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _uploadTile(c),
              ),
          if (_downloads.isNotEmpty) ...[
            const SizedBox(height: 22),
            Text(
              'Downloads',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary(context),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Cards you’ve saved — grab them again on any device.',
              style: TextStyle(
                color: AppColors.textTertiary(context),
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 12),
            _downloadsGrid(),
          ],
        ],
      ),
    );
  }

  Widget _downloadsGrid() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 150,
        childAspectRatio: 0.66,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: _downloads.length,
      itemBuilder: (_, i) => StoopCardTile(
        card: _downloads[i],
        onTap: () => showStoopDetail(context, _downloads[i].id),
      ),
    );
  }

  Widget _uploadTile(StoopCharacter c) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardOf(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  c.name,
                  style: TextStyle(
                    color: AppColors.textPrimary(context),
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
              _statusChip(c),
            ],
          ),
          if (c.summary.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              c.summary,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: AppColors.textSecondary(context)),
            ),
          ],
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  'v${c.version} · ${c.downloadCount} downloads'
                  '${c.nsfw ? ' · NSFW' : ''}',
                  style: TextStyle(
                    color: AppColors.textTertiary(context),
                    fontSize: 12,
                  ),
                ),
              ),
              // Update publishes a new version of THIS post in place — for solo
              // characters and (now that groups carry a portable stable id) group
              // cards alike, each through its own editor + publish flow.
              OutlinedButton.icon(
                  onPressed: () => c.type == 'GROUP'
                      ? _startGroupUpdate(c)
                      : _startUpdate(c),
                  icon: const Icon(Icons.autorenew_rounded, size: 15),
                  label: const Text('Update'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textSecondary(context),
                    side: BorderSide(color: AppColors.borderOf(context)),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    minimumSize: const Size(0, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                ),
            ],
          ),
          if (c.isRejected && (c.rejectionNote?.isNotEmpty ?? false)) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.resolve(
                  context,
                  Colors.redAccent,
                  Colors.red.shade700,
                ).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Moderator: ${c.rejectionNote}',
                style: TextStyle(
                  color: AppColors.resolve(
                    context,
                    Colors.redAccent,
                    Colors.red.shade700,
                  ),
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _statusChip(StoopCharacter c) {
    late Color color;
    late String label;
    if (c.isApproved) {
      color = AppColors.resolve(context, Colors.greenAccent, Colors.green);
      label = 'Approved';
    } else if (c.isRejected) {
      color = AppColors.resolve(context, Colors.redAccent, Colors.red.shade700);
      label = c.status == 'TAKEN_DOWN' ? 'Taken down' : 'Rejected';
    } else {
      color = AppColors.resolve(
        context,
        Colors.amberAccent,
        Colors.amber.shade800,
      );
      label = 'Pending review';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _hint(IconData icon, String text, {bool retry = false}) {
    return ListView(
      // ListView so RefreshIndicator/scroll works for the empty + error states.
      padding: const EdgeInsets.all(40),
      children: [
        const SizedBox(height: 60),
        Icon(icon, size: 48, color: AppColors.iconSecondary(context)),
        const SizedBox(height: 14),
        Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textTertiary(context)),
        ),
        if (retry) ...[
          const SizedBox(height: 16),
          Center(
            child: OutlinedButton(onPressed: _load, child: const Text('Retry')),
          ),
        ],
      ],
    );
  }
}
