// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/providers/auth_state.dart';
import 'package:front_porch_ai/services/backporch/backporch.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/pages/pages.dart';
import 'package:front_porch_ai/ui/pages/repository/stoop_avatar.dart';
import 'package:front_porch_ai/ui/pages/repository/stoop_glass.dart';
import 'package:front_porch_ai/ui/pages/repository/stoop_upload_page.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// One of the signed-in user's own Stoop uploads on the profile tab, as a
/// GRID tile (maintainer request 2026-08-01 — a text list "will look really
/// bad" at scale): card art with the moderation status chip riding it, name,
/// version/download meta, compact Update/Delete icons, and — for rejections —
/// a tappable ember "Moderator note" pill over the art.
class StoopMyUploadTile extends StatelessWidget {
  final StoopCharacter character;

  /// Called after any action that changes the server list (update submitted,
  /// card deleted) so the parent can reload.
  final VoidCallback onChanged;

  const StoopMyUploadTile({
    super.key,
    required this.character,
    required this.onChanged,
  });

  // Publish a new version of an already-shared character IN PLACE. Finds the
  // local library card this post came from (by the card's stable id, else by
  // name) and opens the wizard locked to it in update mode.
  Future<void> _startUpdate(BuildContext context) async {
    final c = character;
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
      if (context.mounted) {
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
    if (saved == null || !context.mounted) return; // backed out without saving
    // 2) Stoop publish step (summary/tags/NSFW/standards → new version in place).
    final updated = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => StoopUploadPage(
          updateCharacter: saved,
          updateStoopId: c.id,
          initialNsfw: c.nsfw,
          initialName: c.name,
          initialSummary: c.summary,
          initialOriginalCreator: c.originalCreator,
          initialCommentsEnabled: c.commentsEnabled,
        ),
      ),
    );
    if (updated == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Update submitted for review.')),
      );
      onChanged();
    }
  }

  // Publish a new version of an already-shared GROUP in place. Finds the local
  // group this post came from (by the portable group stable id, else by name),
  // opens the full group editor (Save → "Next", which saves locally + returns
  // the group), then the Stoop publish step re-publishes the same post.
  Future<void> _startGroupUpdate(BuildContext context) async {
    final c = character;
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
      if (context.mounted) {
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
    if (saved == null || !context.mounted) return; // backed out without saving
    // 2) Stoop publish step (summary/tags/NSFW/standards → new version in place).
    final updated = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => StoopUploadPage(
          updateGroup: saved,
          updateStoopId: c.id,
          initialNsfw: c.nsfw,
          initialName: c.name,
          initialSummary: c.summary,
          initialOriginalCreator: c.originalCreator,
          initialCommentsEnabled: c.commentsEnabled,
        ),
      ),
    );
    if (updated == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Update submitted for review.')),
      );
      onChanged();
    }
  }

  // Delete this upload from The Stoop (owner-only server-side). Confirm-first;
  // copies people already downloaded stay theirs.
  Future<void> _confirmDelete(BuildContext context) async {
    final c = character;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: stoopCard2(ctx),
        title: Text(
          'Take “${c.name}” off The Stoop?',
          style: TextStyle(color: stoopCream(ctx)),
        ),
        content: Text(
          'This removes the card from the porch permanently — its votes and '
          'download count go with it. Copies other people already downloaded '
          'are theirs to keep. Your local library copy is not touched.',
          style: TextStyle(color: stoopCream2(ctx)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.stoopEmber,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete from The Stoop'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final token = context.read<AuthState>().accessToken;
    if (token == null) return;
    try {
      await BackporchApi().deleteCharacter(token, c.id);
      messenger.showSnackBar(
        SnackBar(content: Text('“${c.name}” was removed from The Stoop.')),
      );
      onChanged();
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Couldn’t delete that. Try again.')),
      );
    }
  }

  // A rejection's moderator note doesn't fit on a grid tile — the ember pill
  // on the art opens it here instead.
  void _showModNote(BuildContext context) {
    final note = character.rejectionNote;
    if (note == null || note.isEmpty) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: stoopCard2(ctx),
        title: Text(
          '“${character.name}” — moderator note',
          style: stoopDisplay(ctx, size: 17),
        ),
        content: Text(note, style: TextStyle(color: stoopEmberText(ctx))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = character;
    final hasNote = c.isRejected && (c.rejectionNote?.isNotEmpty ?? false);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: stoopCardGradient(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: stoopBorder(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                StoopAvatar(assetId: c.primaryAssetId),
                Positioned(top: 8, left: 8, child: _statusChip(context)),
                if (hasNote)
                  Positioned(
                    left: 8,
                    right: 8,
                    bottom: 8,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: () => _showModNote(context),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.stoopEmber.withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Text(
                          '⚠ Moderator note',
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppColors.stoopAmberInk,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 4, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  c.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: stoopDisplay(context, size: 14),
                ),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'v${c.version} · ⬇ ${c.downloadCount}'
                        '${c.nsfw ? ' · 18+' : ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: stoopMute(context),
                          fontSize: 11.5,
                        ),
                      ),
                    ),
                    // Update publishes a new version of THIS post in place —
                    // solo and group cards alike, each through its own editor +
                    // publish flow. World posts are new-upload-only for now
                    // (re-share from the wizard); routing them to the
                    // character path would just dead-end.
                    if (c.type != 'WORLD')
                      _iconAction(
                        context,
                        Icons.autorenew_rounded,
                        'Update (publish a new version)',
                        stoopCream2(context),
                        () => c.type == 'GROUP'
                            ? _startGroupUpdate(context)
                            : _startUpdate(context),
                      ),
                    _iconAction(
                      context,
                      Icons.delete_outline_rounded,
                      'Delete from The Stoop',
                      stoopEmberText(context),
                      () => _confirmDelete(context),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _iconAction(
    BuildContext context,
    IconData icon,
    String tooltip,
    Color color,
    VoidCallback onTap,
  ) {
    return IconButton(
      onPressed: onTap,
      tooltip: tooltip,
      icon: Icon(icon, size: 17, color: color),
      padding: const EdgeInsets.all(4),
      constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
      visualDensity: VisualDensity.compact,
    );
  }

  // Hub .hub-status pills: PENDING amber, APPROVED teal, REJECTED ember.
  Widget _statusChip(BuildContext context) {
    final c = character;
    late Color color;
    late Color hairline;
    late String label;
    if (c.isApproved) {
      color = stoopTealText(context);
      hairline = AppColors.stoopTeal.withValues(alpha: 0.35);
      label = 'APPROVED';
    } else if (c.isRejected) {
      color = stoopEmberText(context);
      hairline = AppColors.stoopEmber.withValues(alpha: 0.4);
      label = c.status == 'TAKEN_DOWN' ? 'TAKEN DOWN' : 'REJECTED';
    } else {
      color = stoopAmberText(context);
      hairline = AppColors.stoopAmber.withValues(alpha: 0.35);
      label = 'PENDING';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: hairline),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}
