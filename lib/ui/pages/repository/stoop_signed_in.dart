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

import 'package:front_porch_ai/ui/pages/repository/stoop_browse_view.dart';
import 'package:front_porch_ai/ui/pages/repository/stoop_home_view.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// The fully signed-in Stoop: a Browse tab (the community grid) and a Mine tab
/// (your uploads + the Share wizard). The account menu lives in the page app bar.
class StoopSignedIn extends StatelessWidget {
  const StoopSignedIn({super.key});

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.resolve(context, Colors.tealAccent, Colors.teal);
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              color: AppColors.surfaceOf(context),
              border: Border(
                bottom: BorderSide(color: AppColors.borderOf(context)),
              ),
            ),
            child: TabBar(
              labelColor: AppColors.textPrimary(context),
              unselectedLabelColor: AppColors.textTertiary(context),
              indicatorColor: accent,
              tabs: const [
                Tab(text: 'Browse'),
                Tab(text: 'Mine'),
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
