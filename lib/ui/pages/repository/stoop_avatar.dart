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

import 'package:front_porch_ai/providers/auth_state.dart';
import 'package:front_porch_ai/services/backporch/backporch.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Loads a Stoop card asset (avatar) by id. The asset endpoint serves only
/// signed-in users, so the request carries the access token as a Bearer header.
/// Falls back to a neutral placeholder while loading or on error.
class StoopAvatar extends StatelessWidget {
  final String? assetId;
  final double? width;
  final double? height;
  final BoxFit fit;
  const StoopAvatar({
    super.key,
    required this.assetId,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
  });

  @override
  Widget build(BuildContext context) {
    final token = context.read<AuthState>().accessToken;
    final id = assetId;
    if (id == null || id.isEmpty || token == null) return _placeholder(context);
    return Image.network(
      BackporchApi().assetUrl(id),
      width: width,
      height: height,
      fit: fit,
      headers: {'Authorization': 'Bearer $token'},
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => _placeholder(context),
      loadingBuilder: (context, child, progress) =>
          progress == null ? child : _placeholder(context, loading: true),
    );
  }

  Widget _placeholder(BuildContext context, {bool loading = false}) {
    return Container(
      width: width,
      height: height,
      color: AppColors.surfaceContainerOf(context),
      alignment: Alignment.center,
      child: loading
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(
              Icons.person_outline,
              color: AppColors.iconSecondary(context),
              size: 32,
            ),
    );
  }
}
