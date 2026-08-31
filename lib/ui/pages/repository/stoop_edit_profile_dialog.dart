// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:provider/provider.dart';

import 'package:front_porch_ai/providers/auth_state.dart';
import 'package:front_porch_ai/services/backporch/backporch.dart';
import 'package:front_porch_ai/ui/pages/repository/stoop_glass.dart';
import 'package:front_porch_ai/ui/pages/repository/stoop_profile_header.dart';
import 'package:front_porch_ai/utils/utils.dart';

/// The Edit Profile dialog from the approved mockup: profile photo (verified
/// email required; live instantly, post-moderated), display name, bio, and up
/// to four links. Returns true when anything was saved.
Future<bool?> showStoopEditProfile(BuildContext context) {
  return showDialog<bool>(
    context: context,
    builder: (_) => const Dialog(
      backgroundColor: Colors.transparent,
      child: _EditProfileCard(),
    ),
  );
}

// Center-crop to a square and cap at 512px, encoded as JPEG. Runs in an
// isolate — decoding a phone-camera PNG on the UI thread would freeze a frame.
Uint8List? _cropSquareJpg(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  final side = decoded.width < decoded.height ? decoded.width : decoded.height;
  final square = img.copyCrop(
    decoded,
    x: (decoded.width - side) ~/ 2,
    y: (decoded.height - side) ~/ 2,
    width: side,
    height: side,
  );
  final sized = side > 512 ? img.copyResize(square, width: 512) : square;
  return Uint8List.fromList(img.encodeJpg(sized, quality: 90));
}

class _EditProfileCard extends StatefulWidget {
  const _EditProfileCard();

  @override
  State<_EditProfileCard> createState() => _EditProfileCardState();
}

class _EditProfileCardState extends State<_EditProfileCard> {
  late final TextEditingController _name;
  late final TextEditingController _bio;
  late final List<TextEditingController> _links;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final u = context.read<AuthState>().user;
    _name = TextEditingController(text: u?.displayName ?? '');
    _bio = TextEditingController(text: u?.bio ?? '');
    _links = List.generate(
      4,
      (i) => TextEditingController(
        text: (u?.profileLinks.length ?? 0) > i ? u!.profileLinks[i] : '',
      ),
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _bio.dispose();
    for (final c in _links) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final auth = context.read<AuthState>();
    final picked = await PickerPrefs.pickFiles(
      category: PickerPrefs.catImage,
      dialogTitle: 'Choose a profile photo',
      type: FileType.custom,
      allowedExtensions: ['png', 'jpg', 'jpeg', 'webp'],
    );
    final bytes = await picked?.firstBytes();
    if (bytes == null || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final cropped = await compute(_cropSquareJpg, bytes);
      if (cropped == null) {
        if (mounted) setState(() => _error = 'Couldn’t read that image.');
        return;
      }
      await auth.uploadAvatar(cropped, 'avatar.jpg');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile photo updated — it’s live.')),
        );
      }
    } on BackporchApiException catch (e) {
      if (mounted) setState(() => _error = _mapError(e.code));
    } catch (_) {
      if (mounted) setState(() => _error = 'Upload failed. Check your connection.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _removePhoto() async {
    setState(() => _busy = true);
    try {
      await context.read<AuthState>().removeAvatar();
    } catch (_) {
      if (mounted) setState(() => _error = 'Couldn’t remove the photo. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    final auth = context.read<AuthState>();
    final u = auth.user;
    if (u == null) return;
    final name = _name.text.trim();
    final bio = _bio.text.trim();
    final links = [
      for (final c in _links)
        if (c.text.trim().isNotEmpty) c.text.trim(),
    ];
    if (name.length < 2) {
      setState(() => _error = 'Display name must be at least 2 characters.');
      return;
    }
    final badLink = links.any(
      (l) => !l.startsWith('http://') && !l.startsWith('https://'),
    );
    if (badLink) {
      setState(() => _error = 'Links must start with http:// or https://.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // Display name is its own endpoint (it can 409 on a taken name) — change
      // it first so a rejection stops the save with everything still editable.
      if (name != u.displayName) await auth.setDisplayName(name);
      if (bio != u.bio || !listEquals(links, u.profileLinks)) {
        await auth.updateProfile(bio: bio, links: links);
      }
      if (mounted) Navigator.of(context).pop(true);
    } on BackporchApiException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = _mapError(e.code);
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Couldn’t save. Check your connection and try again.';
        });
      }
    }
  }

  String _mapError(String code) {
    switch (code) {
      case 'display_name_taken':
        return 'That display name is already taken — pick another.';
      case 'email_not_verified':
        return 'Confirm your email first — profile photos need a verified '
            'address.';
      case 'avatar_locked':
        return 'A moderator has disabled profile pictures for this account.';
      case 'unsupported_image_type':
        return 'Use a PNG, JPEG, or WebP image.';
      case 'invalid_input':
        return 'Please double-check the form.';
      default:
        return 'Something went wrong. Try again.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final u = context.watch<AuthState>().user;
    if (u == null) return const SizedBox.shrink();
    final canPhoto = u.emailVerified && !u.avatarLocked;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: stoopPanel(context),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Edit your profile', style: stoopDisplay(context, size: 19)),
              const SizedBox(height: 2),
              Text(
                'This is what visitors see on your public porch page.',
                style: TextStyle(color: stoopMute(context), fontSize: 13),
              ),
              const SizedBox(height: 16),
              _label('Profile photo'),
              Row(
                children: [
                  StoopCreatorAvatar(
                    assetId: u.avatarAssetId,
                    name: u.displayName,
                    size: 52,
                  ),
                  const SizedBox(width: 14),
                  OutlinedButton(
                    onPressed: _busy || !canPhoto ? null : _pickPhoto,
                    style: _ghost(context),
                    child: Text(
                      u.avatarAssetId == null
                          ? 'Choose photo…'
                          : 'Change photo…',
                    ),
                  ),
                  if (u.avatarAssetId != null) ...[
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: _busy ? null : _removePhoto,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: stoopEmberText(context),
                        side: BorderSide(
                          color: stoopEmberText(context).withValues(alpha: 0.5),
                        ),
                      ),
                      child: const Text('Remove'),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 5),
              Text(
                u.avatarLocked
                    ? 'A moderator has disabled profile pictures for this '
                          'account. You can appeal from your inbox.'
                    : !u.emailVerified
                    ? 'Confirm your email to add a photo (resend from the '
                          'banner on your profile).'
                    : 'Square crop, shows immediately. Keep it porch-front '
                          'friendly — moderators can remove an avatar that '
                          'crosses the line, and removals come with a warning.',
                style: TextStyle(color: stoopFaint(context), fontSize: 11.5),
              ),
              const SizedBox(height: 14),
              _label('Display name'),
              TextField(
                controller: _name,
                maxLength: 40,
                enabled: !_busy,
                style: TextStyle(color: stoopCream(context)),
                decoration: stoopInput(
                  context,
                  'How others see you',
                  counterText: '',
                ),
              ),
              const SizedBox(height: 5),
              Text(
                '2–40 characters. If it’s taken you’ll be told right here; '
                'changing it also changes your public page link.',
                style: TextStyle(color: stoopFaint(context), fontSize: 11.5),
              ),
              const SizedBox(height: 14),
              _label('Bio'),
              TextField(
                controller: _bio,
                maxLength: 300,
                maxLines: 3,
                enabled: !_busy,
                style: TextStyle(color: stoopCream(context)),
                decoration: stoopInput(
                  context,
                  'A short bio for your public porch page',
                ),
              ),
              const SizedBox(height: 8),
              _label('Links (up to 4)'),
              for (final (i, c) in _links.indexed) ...[
                TextField(
                  controller: c,
                  enabled: !_busy,
                  style: TextStyle(color: stoopCream(context)),
                  decoration: stoopInput(
                    context,
                    i == 0 ? 'https:// — your chub / Backyard / socials' : 'https://…',
                  ),
                ),
                if (i < _links.length - 1) const SizedBox(height: 8),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(
                    color: stoopEmberText(context),
                    fontSize: 13,
                  ),
                ),
              ],
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: _busy
                        ? null
                        : () => Navigator.of(context).pop(false),
                    style: _ghost(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 10),
                  StoopAmberButton(
                    label: 'Save profile',
                    busy: _busy,
                    onPressed: _busy ? null : _save,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 11,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          color: stoopMute(context),
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  ButtonStyle _ghost(BuildContext context) {
    return OutlinedButton.styleFrom(
      foregroundColor: stoopCream2(context),
      side: BorderSide(color: stoopBorderHi(context)),
    );
  }
}

