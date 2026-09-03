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

import 'package:front_porch_ai/providers/auth_state.dart';
import 'package:front_porch_ai/services/backporch/backporch.dart';
import 'package:front_porch_ai/ui/pages/repository/stoop_card_detail_page.dart';
import 'package:front_porch_ai/ui/pages/repository/stoop_card_tile.dart';
import 'package:front_porch_ai/ui/pages/repository/stoop_creator_page.dart';
import 'package:front_porch_ai/ui/pages/repository/stoop_edit_profile_dialog.dart';
import 'package:front_porch_ai/ui/pages/repository/stoop_glass.dart';
import 'package:front_porch_ai/ui/pages/repository/stoop_my_upload_tile.dart';
import 'package:front_porch_ai/ui/pages/repository/stoop_profile_header.dart';
import 'package:front_porch_ai/ui/pages/repository/stoop_upload_page.dart';
import 'package:front_porch_ai/ui/pages/repository/stoop_verified_badge.dart';
import 'package:front_porch_ai/ui/pages/repository/stoop_verify_banner.dart';

/// The signed-in @you tab, per the approved profile mockup: a real identity
/// header (avatar, join date, followers + lifetime stats, bio, links) with
/// Edit profile + Share, then your uploads with moderation status, the
/// creators you follow, and your download history.
class StoopHomeView extends StatefulWidget {
  const StoopHomeView({super.key});

  @override
  State<StoopHomeView> createState() => _StoopHomeViewState();
}

class _StoopHomeViewState extends State<StoopHomeView> {
  final _api = BackporchApi();
  bool _loading = true;
  String? _error;
  StoopCreator? _profile;
  List<StoopCharacter> _mine = const [];
  List<StoopCard> _downloads = const [];
  List<StoopFollowedCreator> _followed = const [];
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
    final auth = context.read<AuthState>();
    final token = auth.accessToken;
    final userId = auth.user?.id;
    if (token == null || userId == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await _api.myCharacters(token);
      // Identity/stats, downloads, and following are non-critical extras: the
      // uploads list still renders when any of them fails.
      StoopCreator? profile;
      List<StoopCard> downloads = const [];
      List<StoopFollowedCreator> followed = const [];
      try {
        profile = await _api.creatorProfile(token, userId);
      } catch (_) {}
      try {
        downloads = await _api.myDownloads(token);
      } catch (_) {}
      try {
        followed = await _api.myFollowing(token);
      } catch (_) {}
      if (mounted) {
        setState(() {
          _mine = items;
          _profile = profile;
          _downloads = downloads;
          _followed = followed;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Couldn’t load your profile. Pull to retry.';
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

  Future<void> _editProfile() async {
    final changed = await showStoopEditProfile(context);
    if (changed == true && mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: stoopBg0(context),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: _body(),
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading) return const StoopLamp();
    if (_error != null) return _hint('🌙', _error!, retry: true);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        children: [
          // Self-hides once the email is confirmed. Surfaced here (not just on
          // the upload page) because sharing AND profile photos both need it.
          const StoopVerifyBanner(),
          _profileHeader(),
          const SizedBox(height: 18),
          _sectionRow(
            'Your cards',
            hint: _mine.isEmpty ? null : '${_mine.length} shared',
            trailing: StoopAmberButton(
              label: 'Share to The Stoop',
              icon: Icons.upload_outlined,
              onPressed: _startUpload,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
          ),
          if (_mine.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Nothing shared yet — tap “Share to The Stoop” to submit a '
                'card for review.',
                style: TextStyle(color: stoopMute(context)),
              ),
            )
          else
            // Art-forward grid (not a list): with many uploads a text list
            // reads terribly, and the art is the identity anyway.
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 190,
                childAspectRatio: 0.62,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: _mine.length,
              itemBuilder: (_, i) =>
                  StoopMyUploadTile(character: _mine[i], onChanged: _load),
            ),
          if (_followed.isNotEmpty) ...[
            const SizedBox(height: 14),
            _sectionRow(
              'Following',
              hint: 'tap a creator to visit their porch',
            ),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [for (final f in _followed) _followedChip(f)],
            ),
          ],
          if (_downloads.isNotEmpty) ...[
            const SizedBox(height: 22),
            _sectionRow('Downloads', hint: 'cards you’ve brought home'),
            _downloadsGrid(),
          ],
        ],
      ),
    );
  }

  Widget _profileHeader() {
    final user = context.watch<AuthState>().user;
    if (user == null) return const SizedBox.shrink();
    // The server profile carries the stats; the AuthState user is the fresher
    // identity (an Edit Profile save updates it instantly, no reload needed).
    final p = _profile;
    final creator = StoopCreator(
      id: user.id,
      displayName: user.displayName,
      verification: user.verification,
      followers: p?.followers ?? 0,
      following: false,
      isMe: true,
      cards: const [],
      bio: user.bio,
      links: user.profileLinks,
      avatarAssetId: user.avatarAssetId,
      createdAt: user.createdAt ?? p?.createdAt,
      stats: p?.stats ?? const StoopCreatorStats(),
    );
    return StoopProfileHeader(
      creator: creator,
      actions: [
        StoopAmberButton(
          label: 'Edit profile',
          icon: Icons.edit_outlined,
          onPressed: _editProfile,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        ),
        OutlinedButton.icon(
          onPressed: () => stoopCopyCreatorLink(
            context,
            id: user.id,
            displayName: user.displayName,
          ),
          icon: const Icon(Icons.link_rounded, size: 16),
          label: const Text('Share'),
          style: OutlinedButton.styleFrom(
            foregroundColor: stoopCream2(context),
            side: BorderSide(color: stoopBorderHi(context)),
          ),
        ),
      ],
    );
  }

  Widget _sectionRow(String title, {String? hint, Widget? trailing}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(title, style: stoopDisplay(context, size: 17)),
          if (hint != null) ...[
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                hint,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: stoopFaint(context), fontSize: 12),
              ),
            ),
          ] else
            const Spacer(),
          ?trailing,
        ],
      ),
    );
  }

  Widget _followedChip(StoopFollowedCreator f) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => StoopCreatorPage(creatorId: f.id)),
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(6, 5, 13, 5),
        decoration: BoxDecoration(
          color: stoopBg1(context),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: stoopBorderHi(context)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            StoopCreatorAvatar(
              assetId: f.avatarAssetId,
              name: f.displayName,
              size: 26,
            ),
            const SizedBox(width: 9),
            Text(
              f.displayName,
              style: TextStyle(color: stoopCream(context), fontSize: 13),
            ),
            StoopVerifiedBadge(verification: f.verification, size: 13),
            const SizedBox(width: 8),
            Text(
              '${f.followers} ${f.followers == 1 ? 'follower' : 'followers'}',
              style: TextStyle(color: stoopFaint(context), fontSize: 11.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _downloadsGrid() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 190,
        childAspectRatio: 0.64,
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

  Widget _hint(String glyph, String text, {bool retry = false}) {
    return ListView(
      // ListView so RefreshIndicator/scroll works for the empty + error states.
      padding: const EdgeInsets.all(40),
      children: [
        const SizedBox(height: 60),
        Text(
          glyph,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 34),
        ),
        const SizedBox(height: 14),
        Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(color: stoopMute(context), height: 1.5),
        ),
        if (retry) ...[
          const SizedBox(height: 16),
          Center(
            child: OutlinedButton(
              onPressed: _load,
              style: OutlinedButton.styleFrom(
                foregroundColor: stoopCream2(context),
                side: BorderSide(color: stoopBorderHi(context)),
              ),
              child: const Text('Retry'),
            ),
          ),
        ],
      ],
    );
  }
}
