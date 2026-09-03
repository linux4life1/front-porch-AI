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
import 'package:front_porch_ai/ui/pages/repository/stoop_browse_view.dart';
import 'package:front_porch_ai/ui/pages/repository/stoop_glass.dart';
import 'package:front_porch_ai/ui/pages/repository/stoop_home_view.dart';
import 'package:front_porch_ai/ui/pages/repository/stoop_verified_badge.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// The fully signed-in Stoop: a Browse tab (the community grid) and a personal
/// tab labeled with the user's own @name (their uploads + the Share wizard).
/// The account menu lives in the page app bar.
class StoopSignedIn extends StatelessWidget {
  const StoopSignedIn({super.key});

  @override
  Widget build(BuildContext context) {
    // The personal tab wears the signed-in display name (like the hub's bar
    // showing who you are) — and live-updates if it's renamed in Account.
    final displayName = context.select<AuthState, String>(
      (a) => a.user?.displayName ?? '',
    );
    final verification = context.select<AuthState, String?>(
      (a) => a.user?.verification,
    );
    // Hub tab bar (.hub-tab): quiet labels, the active one amber with an
    // amber underline.
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              color: stoopBg0(context),
              border: Border(bottom: BorderSide(color: stoopBorder(context))),
            ),
            child: TabBar(
              labelColor: stoopAmberText(context),
              unselectedLabelColor: stoopMute(context),
              indicatorColor: AppColors.stoopAmber,
              dividerColor: Colors.transparent,
              labelStyle: const TextStyle(fontWeight: FontWeight.w600),
              tabs: [
                const Tab(text: 'Browse'),
                Tab(
                  // Long names ellipsize instead of stretching the bar.
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 180),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            displayName.isEmpty ? 'Mine' : '@$displayName',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        StoopVerifiedBadge(
                          verification: verification,
                          size: 13,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Expanded(
            child: TabBarView(children: [StoopBrowseView(), StoopHomeView()]),
          ),
        ],
      ),
    );
  }
}
