// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

part of 'stoop_upload_page.dart';

extension _StoopUploadPageStatePublish on _StoopUploadPageState {
  Future<void> _publish() async {
    final world = _selectedWorld;
    if (world != null) {
      await _publishWorld(world);
      return;
    }
    final group = _selectedGroup;
    if (group != null) {
      await _publishGroup(group);
      return;
    }
    final card = _selected;
    if (card == null) return;
    // Cover = the ★ starred avatar (a look/expression) when set, else the
    // library portrait. Gate on the resolved cover (not imagePath) so a
    // portrait-less card that has a starred look can still upload.
    final cover = context.read<CharacterRepository>().coverImageFileFor(card);
    final noCover = cover == null || !cover.existsSync(); // io-ok: share
    if (noCover) {
      rebuildState(() => _error = 'This character has no avatar to upload.');
      return;
    }
    final completeness = StoopCardCompleteness.assess(card.toJson(), 'SOLO');
    if (completeness.incomplete) {
      rebuildState(() => _error = completeness.message);
      return;
    }
    rebuildState(() {
      _busy = true;
      _error = null;
    });
    final auth = context.read<AuthState>();
    try {
      final bytes = await cover.readAsBytes();
      final ext = cover.path.split('.').last.toLowerCase();
      // Content is edited in the full character editor before this step (update
      // flow), so the card is already current — publish it as-is.
      final payload = {
        'name': _name.text.trim(),
        'summary': _summary.text.trim(),
        'type': 'SOLO',
        // Belt-and-braces: the switch is forced too, but a card with intimate
        // preferences must never leave here with the flag off. Solo reads the
        // rule off `card` — the very object being published.
        'nsfw': _adult.value || stoopForcesAdult(card, null),
        // Client-side / future hub field. Default false. Not deployed to API.
        'commentsEnabled': _commentsEnabled,
        'tags': _tags,
        'card': card.toJson(),
        'changelog': widget.isUpdate ? 'Updated' : 'Initial upload',
        // Attribution ('' = own work; on update, '' clears an old credit).
        'originalCreator': _originalCreator.text.trim(),
      };
      if (widget.isUpdate) {
        // In-place new version of the existing post (keeps id/downloads/score).
        final result = await BackporchApi().publishVersion(
          accessToken: auth.accessToken!,
          characterId: widget.updateStoopId!,
          payload: payload,
          avatarBytes: bytes,
          avatarFilename: 'avatar.$ext',
        );
        _rememberCommentsOptIn(
          result.id.isNotEmpty ? result.id : widget.updateStoopId!,
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
      if (mounted) Navigator.pop(context, true);
    } on BackporchApiException catch (e) {
      if (mounted) {
        rebuildState(() => _error = _mapError(e.code, detail: e.detail));
      }
    } catch (_) {
      if (mounted) {
        rebuildState(
          () => _error = 'Couldn’t share that character. Try again.',
        );
      }
    } finally {
      if (mounted) rebuildState(() => _busy = false);
    }
  }

  Future<void> _publishGroup(GroupChat group) async {
    rebuildState(() {
      _busy = true;
      _error = null;
    });
    final auth = context.read<AuthState>();
    try {
      final exporter = GroupCardExporter(
        context.read<GroupChatRepository>(),
        context.read<StorageService>(),
        liveDatabase(context),
      );
      final groupCard = await exporter.buildGroupCard(group);
      if (groupCard == null) {
        if (mounted) {
          rebuildState(() => _error = 'This group has no members to share.');
        }
        return;
      }
      final completeness = StoopCardCompleteness.assess(
        groupCard.toJson(),
        'GROUP',
      );
      if (completeness.incomplete) {
        if (mounted) rebuildState(() => _error = completeness.message);
        return;
      }
      // Decide 18+ from the bytes we are about to upload, not from the wizard's
      // advisory cast read. If the two disagree the screen is corrected too, so
      // a failed upload can't leave Review contradicting the payload.
      final forcedAdult = stoopGroupCardForcesAdult(groupCard);
      if (forcedAdult && !_adult.value && mounted) {
        rebuildState(() => _adult.reconcile(forced: true));
      }
      // A member-avatar collage is the Stoop cover; full member avatars still
      // travel inside the card JSON for a faithful download.
      final avatarPaths = groupCard.members
          .map((c) => c.imagePath)
          .whereType<String>()
          .where((p) => p.isNotEmpty)
          .toList();
      if (avatarPaths.isEmpty) {
        if (mounted) {
          rebuildState(
            () => _error =
                'This group’s members need avatars before it can be shared.',
          );
        }
        return;
      }
      final collage = await createGroupAvatarCollage(avatarPaths);
      final payload = {
        'name': _name.text.trim(),
        'summary': _summary.text.trim(),
        'type': 'GROUP',
        'nsfw': _adult.value || forcedAdult, // see the SOLO payload above
        'commentsEnabled': _commentsEnabled,
        'tags': _tags,
        'card': groupCard.toJson(),
        'changelog': widget.isUpdate ? 'Updated' : 'Initial upload',
        // Attribution ('' = own work; on update, '' clears an old credit).
        'originalCreator': _originalCreator.text.trim(),
      };
      if (widget.isUpdate) {
        // In-place new version of the existing group post (keeps id/downloads/
        // score). The group card now carries a stable id, so this is the same
        // in-place path solo characters use.
        final result = await BackporchApi().publishVersion(
          accessToken: auth.accessToken!,
          characterId: widget.updateStoopId!,
          payload: payload,
          avatarBytes: collage,
          avatarFilename: 'cover.png',
        );
        _rememberCommentsOptIn(
          result.id.isNotEmpty ? result.id : widget.updateStoopId!,
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
      if (mounted) Navigator.pop(context, true);
    } on BackporchApiException catch (e) {
      if (mounted) {
        rebuildState(() => _error = _mapError(e.code, detail: e.detail));
      }
    } catch (_) {
      if (mounted) {
        rebuildState(() => _error = 'Couldn’t share that group. Try again.');
      }
    } finally {
      if (mounted) rebuildState(() => _busy = false);
    }
  }

  // Publish a place as a WORLD card (same moderation queue as characters).
  // The payload/cover work lives in publishStoopWorld (stoop_world_share.dart);
  // this is just the wizard's busy/error scaffolding, mirroring _publishGroup.
  Future<void> _publishWorld(World world) async {
    rebuildState(() {
      _busy = true;
      _error = null;
    });
    final auth = context.read<AuthState>();
    try {
      final validation = await publishStoopWorld(
        api: BackporchApi(),
        repo: context.read<WorldRepository>(),
        accessToken: auth.accessToken!,
        world: world,
        name: _name.text.trim(),
        summary: _summary.text.trim(),
        nsfw: _adult.value,
        tags: _tags,
        originalCreator: _originalCreator.text.trim(),
        commentsEnabled: _commentsEnabled,
      );
      if (validation != null) {
        if (mounted) rebuildState(() => _error = validation);
        return;
      }
      if (mounted) Navigator.pop(context, true);
    } on BackporchApiException catch (e) {
      if (mounted) {
        rebuildState(() => _error = _mapError(e.code, detail: e.detail));
      }
    } catch (_) {
      if (mounted) {
        rebuildState(() => _error = 'Couldn’t share that place. Try again.');
      }
    } finally {
      if (mounted) rebuildState(() => _busy = false);
    }
  }

  void _rememberCommentsOptIn(String cardId) {
    StoopCommentsOptIn.instance.setPublished(cardId, _commentsEnabled);
  }
}
