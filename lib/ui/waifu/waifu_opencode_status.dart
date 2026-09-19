// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/opencode/opencode.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Compact installed-vs-GitHub-latest line in the Waifu sidebar.
class WaifuOpenCodeStatus extends StatefulWidget {
  const WaifuOpenCodeStatus({super.key});

  @override
  State<WaifuOpenCodeStatus> createState() => _WaifuOpenCodeStatusState();
}

class _WaifuOpenCodeStatusState extends State<WaifuOpenCodeStatus> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        final mgr = context.read<OpenCodeManager>();
        mgr.refreshInstalled();
        mgr.maybeAutoCheckRemoteVersion();
      } on ProviderNotFoundException {
        return;
      }
    });
  }

  VoidCallback? _onPressed(OpenCodeManager mgr) {
    if (mgr.isDownloading || mgr.isCheckingVersion) return null;
    if (mgr.installedVersion == null || mgr.isUpdateAvailable) {
      return () => mgr.upgrade();
    }
    if (mgr.versionError != null || mgr.remoteVersion == null) {
      return () => mgr.checkRemoteVersion();
    }
    return null;
  }

  bool _showTap(OpenCodeManager mgr) {
    if (mgr.installedVersion == null) return true;
    if (mgr.versionError != null) return true;
    if (mgr.remoteVersion == null) return true;
    return mgr.isUpdateAvailable;
  }

  @override
  Widget build(BuildContext context) {
    OpenCodeManager? mgr;
    try {
      mgr = context.watch<OpenCodeManager>();
    } on ProviderNotFoundException {
      return const SizedBox.shrink();
    }
    final honesty = openCodeUpgradeHonesty(
      installed: mgr.installedVersion,
      remote: mgr.remoteVersion,
      megabytes: mgr.downloadMegabytes,
    );
    return Padding(
      key: const Key('waifu-opencode-status'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            honesty,
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary(context),
            ),
          ),
          if (_showTap(mgr))
            TextButton(
              key: const Key('waifu-opencode-upgrade'),
              onPressed: _onPressed(mgr),
              child: Text(
                openCodeUpgradeButtonLabel(
                  installed: mgr.installedVersion,
                  remote: mgr.remoteVersion,
                  versionError: mgr.versionError,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
