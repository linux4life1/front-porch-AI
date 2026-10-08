// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/providers/auth_state.dart';
import 'package:front_porch_ai/services/backporch/backporch.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/ui/pages/repository/stoop_glass.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Image source for a Stoop card asset, served through [StoopAssetCache]
/// (disk cache + fetch cap). Equal on asset id and variant only, so Flutter's
/// in-memory cache keeps the decoded picture across token refreshes.
class StoopAssetImage extends ImageProvider<StoopAssetImage> {
  const StoopAssetImage(
    this.cache,
    this.assetId, {
    required this.thumb,
    required this.token,
  });

  final StoopAssetCache cache;
  final String assetId;
  final bool thumb;
  final String token;

  @override
  Future<StoopAssetImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<StoopAssetImage>(this);

  @override
  ImageStreamCompleter loadImage(
    StoopAssetImage key,
    ImageDecoderCallback decode,
  ) => MultiFrameImageStreamCompleter(
    codec: _codec(decode),
    scale: 1.0,
    debugLabel: 'stoop:$assetId${thumb ? ':t' : ':f'}',
  );

  Future<ui.Codec> _codec(ImageDecoderCallback decode) async {
    final bytes = await cache.bytes(assetId, thumb: thumb, token: token);
    return decode(await ui.ImmutableBuffer.fromUint8List(bytes));
  }

  @override
  bool operator ==(Object other) =>
      other is StoopAssetImage &&
      other.assetId == assetId &&
      other.thumb == thumb;

  @override
  int get hashCode => Object.hash(assetId, thumb);
}

/// Shows a Stoop card asset (avatar) by id. The asset endpoint serves only
/// signed-in users, so the fetch carries the access token.
/// Falls back to a neutral placeholder while loading or on error.
///
/// Like the hub, tiles show the postcard [thumb]; only the card page asks
/// for the original (`thumb: false`), and it shows the thumb — usually
/// already cached from the grid — until the original has decoded.
///
/// Crops anchor to the top like the hub (`object-position: center top`):
/// card art is portrait, and a centred crop in a square box takes the head.
class StoopAvatar extends StatelessWidget {
  final String? assetId;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Alignment alignment;
  final bool thumb;
  const StoopAvatar({
    super.key,
    required this.assetId,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.topCenter,
    this.thumb = true,
  });

  @override
  Widget build(BuildContext context) {
    final token = context.read<AuthState>().accessToken;
    final id = assetId;
    if (id == null || id.isEmpty || token == null) return _placeholder(context);
    final cache = StoopAssetCache.shared(
      context.read<StorageService>().stoopAssetCacheDir,
    );
    final small = _image(context, cache, id, token, thumb: true);
    if (thumb) return small;
    return _image(context, cache, id, token, thumb: false, standIn: small);
  }

  Widget _image(
    BuildContext context,
    StoopAssetCache cache,
    String id,
    String token, {
    required bool thumb,
    Widget? standIn,
  }) {
    return Image(
      image: StoopAssetImage(cache, id, thumb: thumb, token: token),
      width: width,
      height: height,
      fit: fit,
      alignment: alignment,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => standIn ?? _placeholder(context),
      // frame is null until the first decoded frame — including the window
      // before the first byte, where loadingBuilder's progress is also null
      // and a natural-height image would lay out at zero height.
      frameBuilder: (context, child, frame, _) => frame == null
          ? (standIn ?? _placeholder(context, loading: true))
          : child,
    );
  }

  // Hub placeholder: a faint lantern on the inset ground (.hub-tile-art).
  // With no height of its own (natural-height art, e.g. the detail page) it
  // holds a portrait box so the layout does not collapse while loading;
  // under a tight box (tiles) AspectRatio just fills it.
  Widget _placeholder(BuildContext context, {bool loading = false}) {
    final box = Container(
      width: width,
      height: height,
      color: stoopBg1(context),
      alignment: Alignment.center,
      child: _placeholderMark(loading),
    );
    return height == null ? AspectRatio(aspectRatio: 3 / 4, child: box) : box;
  }

  Widget _placeholderMark(bool loading) {
    return loading
        ? const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.stoopAmber,
            ),
          )
        : const Opacity(
            opacity: 0.35,
            child: Text('🏮', style: TextStyle(fontSize: 30)),
          );
  }
}
