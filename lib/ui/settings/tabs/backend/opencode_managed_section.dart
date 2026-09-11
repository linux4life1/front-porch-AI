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
import 'package:front_porch_ai/ui/settings/widgets/section_header.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Waifu Coder's managed OpenCode — same shape as the Kobold download row.
/// Tap installs the pin into the closet. Never Homebrew, never latest-on-launch.
class OpenCodeManagedSection extends StatefulWidget {
  const OpenCodeManagedSection({super.key});

  @override
  State<OpenCodeManagedSection> createState() => _OpenCodeManagedSectionState();
}

class _OpenCodeManagedSectionState extends State<OpenCodeManagedSection> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final mgr = context.read<OpenCodeManager>();
      mgr.refreshInstalled();
      mgr.checkRemoteVersion();
    });
  }

  @override
  Widget build(BuildContext context) {
    final mgr = context.watch<OpenCodeManager>();
    final amber = AppColors.porchAmberOf(context);
    final honesty = openCodeUpgradeHonesty(
      installed: mgr.installedVersion,
      pinned: mgr.pinnedVersion,
      remote: mgr.remoteVersion,
      megabytes: mgr.pinDownloadMegabytes,
    );
    final label = openCodeUpgradeButtonLabel(
      installed: mgr.installedVersion,
      pinned: mgr.pinnedVersion,
    );
    return Column(
      key: const Key('opencode-managed-section'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        const SectionHeader('OpenCode (Waifu Coder)'),
        const SizedBox(height: 12),
        Text(
          honesty,
          key: const Key('opencode-upgrade-honesty'),
          style: TextStyle(
            fontSize: 13,
            height: 1.35,
            color: AppColors.textSecondary(context),
          ),
        ),
        if (mgr.versionError != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              mgr.versionError!,
              style: TextStyle(color: AppColors.negativeAccentOf(context)),
            ),
          ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text(
                mgr.closet.binaryPath,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(fontSize: 10),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (mgr.isDownloading || mgr.isCheckingVersion)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              ElevatedButton(
                key: const Key('opencode-upgrade-tap'),
                onPressed: mgr.needsPinDownload
                    ? () => mgr.upgradeToPin()
                    : null,
                child: Text(label),
              ),
          ],
        ),
        if (mgr.isDownloading)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: LinearProgressIndicator(
              value: mgr.downloadProgress,
              color: amber,
            ),
          ),
      ],
    );
  }
}
