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
import 'package:front_porch_ai/ui/pages/repository/stoop_adult_lock_banner.dart';
import 'package:front_porch_ai/ui/pages/repository/stoop_world_share.dart';
import 'package:front_porch_ai/utils/utils.dart';

/// User-facing text for a Stoop share failure [code].
String stoopUploadErrorMessage(String code, {String? detail}) {
  switch (code) {
    case 'policy_not_accepted':
      return 'Please accept the Acceptable Use Policy before sharing.';
    case 'email_not_verified':
      return 'Confirm your email address before sharing — check your inbox '
          'for the link we sent. Browsing and downloading still work.';
    case 'unsupported_image_type':
      return 'That avatar image type isn’t supported (use PNG, JPG, or WebP).';
    case 'file_too_large':
      return 'That avatar image is too large.';
    case 'storage_unavailable':
      return 'The Stoop’s storage is unavailable right now. Try again later.';
    case 'avatar_required':
      return 'This character needs an avatar image to be shared.';
    case 'incomplete_card':
      return (detail != null && detail.isNotEmpty)
          ? detail
          : 'This card is missing required fields (first message, '
                'description/personality, or scenario). Fill them in the '
                'editor and try again.';
    default:
      return 'Couldn’t share that character. Check your connection and retry.';
  }
}

/// Publishes the Stoop upload wizard's pick (character, group, or place).
///
/// The wizard owns busy/error display; this reports through [onStart]
/// (busy on, error cleared), [onError], [onAdultForced] and [onIdle] (busy
/// off), and pops [context] with `true` once a card is submitted.
class StoopUploadPublisher {
  final BuildContext context;
  final TextEditingController name;
  final TextEditingController summary;
  final TextEditingController originalCreator;
  final StoopAdultFlag adult;
  final List<String> tags;
  final bool commentsEnabled;
  final bool isUpdate;
  final String? updateStoopId;
  final VoidCallback onStart;
  final ValueChanged<String?> onError;
  final VoidCallback onAdultForced;
  final VoidCallback onIdle;

  const StoopUploadPublisher({
    required this.context,
    required this.name,
    required this.summary,
    required this.originalCreator,
    required this.adult,
    required this.tags,
    required this.commentsEnabled,
    required this.isUpdate,
    required this.updateStoopId,
    required this.onStart,
    required this.onError,
    required this.onAdultForced,
    required this.onIdle,
  });

  Future<void> publish({
    required CharacterCard? card,
    required GroupChat? group,
    required World? world,
  }) async {
    if (world != null) {
      await _publishWorld(world);
      return;
    }
    if (group != null) {
      await _publishGroup(group);
      return;
    }
    if (card == null) return;
    // Cover = the ★ starred avatar (a look/expression) when set, else the
    // library portrait. Gate on the resolved cover (not imagePath) so a
    // portrait-less card that has a starred look can still upload.
    final cover = context.read<CharacterRepository>().coverImageFileFor(card);
    final noCover = cover == null || !cover.existsSync(); // io-ok: share
    if (noCover) {
      onError('This character has no avatar to upload.');
      return;
    }
    final completeness = StoopCardCompleteness.assess(card.toJson(), 'SOLO');
    if (completeness.incomplete) {
      onError(completeness.message);
      return;
    }
    onStart();
    final auth = context.read<AuthState>();
    try {
      final bytes = await cover.readAsBytes();
      final ext = cover.path.split('.').last.toLowerCase();
      // Content is edited in the full character editor before this step (update
      // flow), so the card is already current — publish it as-is.
      final payload = {
        'name': name.text.trim(),
        'summary': summary.text.trim(),
        'type': 'SOLO',
        // Belt-and-braces: the switch is forced too, but a card with intimate
        // preferences must never leave here with the flag off. Solo reads the
        // rule off `card` — the very object being published.
        'nsfw': adult.value || stoopForcesAdult(card, null),
        // Client-side / future hub field. Default false. Not deployed to API.
        'commentsEnabled': commentsEnabled,
        'tags': tags,
        'card': card.toJson(),
        'changelog': isUpdate ? 'Updated' : 'Initial upload',
        // Attribution ('' = own work; on update, '' clears an old credit).
        'originalCreator': originalCreator.text.trim(),
      };
      if (isUpdate) {
        // In-place new version of the existing post (keeps id/downloads/score).
        final result = await BackporchApi().publishVersion(
          accessToken: auth.accessToken!,
          characterId: updateStoopId!,
          payload: payload,
          avatarBytes: bytes,
          avatarFilename: 'avatar.$ext',
        );
        _rememberCommentsOptIn(
          result.id.isNotEmpty ? result.id : updateStoopId!,
        );
      } else {
        final result = await BackporchApi().uploadCharacter(
          accessToken: auth.accessToken!,
          payload: payload,
          avatarBytes: bytes,
          avatarFilename: 'avatar.$ext',
        );
        _rememberCommentsOptIn(result.id);
      }
      if (context.mounted) Navigator.pop(context, true);
    } on BackporchApiException catch (e) {
      if (context.mounted) {
        onError(stoopUploadErrorMessage(e.code, detail: e.detail));
      }
    } catch (_) {
      if (context.mounted) {
        onError('Couldn’t share that character. Try again.');
      }
    } finally {
      if (context.mounted) onIdle();
    }
  }

  Future<void> _publishGroup(GroupChat group) async {
    onStart();
    final auth = context.read<AuthState>();
    try {
      final exporter = GroupCardExporter(
        context.read<GroupChatRepository>(),
        context.read<StorageService>(),
        liveDatabase(context),
      );
      final groupCard = await exporter.buildGroupCard(group);
      if (groupCard == null) {
        if (context.mounted) {
          onError('This group has no members to share.');
        }
        return;
      }
      final completeness = StoopCardCompleteness.assess(
        groupCard.toJson(),
        'GROUP',
      );
      if (completeness.incomplete) {
        if (context.mounted) onError(completeness.message);
        return;
      }
      // Decide 18+ from the bytes we are about to upload, not from the wizard's
      // advisory cast read. If the two disagree the screen is corrected too, so
      // a failed upload can't leave Review contradicting the payload.
      final forcedAdult = stoopGroupCardForcesAdult(groupCard);
      if (forcedAdult && !adult.value && context.mounted) {
        onAdultForced();
      }
      // A member-avatar collage is the Stoop cover; full member avatars still
      // travel inside the card JSON for a faithful download.
      final avatarPaths = groupCard.members
          .map((c) => c.imagePath)
          .whereType<String>()
          .where((p) => p.isNotEmpty)
          .toList();
      if (avatarPaths.isEmpty) {
        if (context.mounted) {
          onError('This group’s members need avatars before it can be shared.');
        }
        return;
      }
      final collage = await createGroupAvatarCollage(avatarPaths);
      final payload = {
        'name': name.text.trim(),
        'summary': summary.text.trim(),
        'type': 'GROUP',
        'nsfw': adult.value || forcedAdult, // see the SOLO payload above
        'commentsEnabled': commentsEnabled,
        'tags': tags,
        'card': groupCard.toJson(),
        'changelog': isUpdate ? 'Updated' : 'Initial upload',
        // Attribution ('' = own work; on update, '' clears an old credit).
        'originalCreator': originalCreator.text.trim(),
      };
      if (isUpdate) {
        // In-place new version of the existing group post (keeps id/downloads/
        // score). The group card now carries a stable id, so this is the same
        // in-place path solo characters use.
        final result = await BackporchApi().publishVersion(
          accessToken: auth.accessToken!,
          characterId: updateStoopId!,
          payload: payload,
          avatarBytes: collage,
          avatarFilename: 'cover.png',
        );
        _rememberCommentsOptIn(
          result.id.isNotEmpty ? result.id : updateStoopId!,
        );
      } else {
        final result = await BackporchApi().uploadCharacter(
          accessToken: auth.accessToken!,
          payload: payload,
          avatarBytes: collage,
          avatarFilename: 'cover.png',
        );
        _rememberCommentsOptIn(result.id);
      }
      if (context.mounted) Navigator.pop(context, true);
    } on BackporchApiException catch (e) {
      if (context.mounted) {
        onError(stoopUploadErrorMessage(e.code, detail: e.detail));
      }
    } catch (_) {
      if (context.mounted) {
        onError('Couldn’t share that group. Try again.');
      }
    } finally {
      if (context.mounted) onIdle();
    }
  }

  // Publish a place as a WORLD card (same moderation queue as characters).
  // The payload/cover work lives in publishStoopWorld (stoop_world_share.dart);
  // this is just the wizard's busy/error scaffolding, mirroring _publishGroup.
  Future<void> _publishWorld(World world) async {
    onStart();
    final auth = context.read<AuthState>();
    try {
      final validation = await publishStoopWorld(
        api: BackporchApi(),
        repo: context.read<WorldRepository>(),
        accessToken: auth.accessToken!,
        world: world,
        name: name.text.trim(),
        summary: summary.text.trim(),
        nsfw: adult.value,
        tags: tags,
        originalCreator: originalCreator.text.trim(),
        commentsEnabled: commentsEnabled,
      );
      if (validation != null) {
        if (context.mounted) onError(validation);
        return;
      }
      if (context.mounted) Navigator.pop(context, true);
    } on BackporchApiException catch (e) {
      if (context.mounted) {
        onError(stoopUploadErrorMessage(e.code, detail: e.detail));
      }
    } catch (_) {
      if (context.mounted) {
        onError('Couldn’t share that place. Try again.');
      }
    } finally {
      if (context.mounted) onIdle();
    }
  }

  void _rememberCommentsOptIn(String cardId) {
    StoopCommentsOptIn.instance.setPublished(cardId, commentsEnabled);
  }
}
