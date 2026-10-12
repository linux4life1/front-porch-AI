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
import 'package:url_launcher/url_launcher.dart';

import 'package:front_porch_ai/app_version.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';

/// Settings → General "About & License" card: version, AGPL notice, and the
/// source-code / license-violation links.
class AboutLicenseCard extends StatelessWidget {
  const AboutLicenseCard({super.key});

  @override
  Widget build(BuildContext context) {
    const repoUrl = 'https://github.com/linux4life1/front-porch-ai';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardOf(context),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Front Porch AI v$appVersion',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary(context),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Free, open-source software © 2026 Front Porch AI, licensed under '
            'the GNU Affero General Public License v3.0. You are free to use, '
            'study, modify, and redistribute it under the AGPL. The complete '
            'source code is available below; if you received this app without '
            'that source, or as part of a closed-source product, that is a '
            'license violation.',
            style: TextStyle(
              color: AppColors.textSecondary(context),
              fontSize: 12,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              ActionChip(
                avatar: const Icon(Icons.code, size: 16),
                label: const Text('Source code'),
                onPressed: () => launchUrl(
                  Uri.parse(repoUrl),
                  mode: LaunchMode.externalApplication,
                ),
              ),
              ActionChip(
                avatar: const Icon(Icons.gavel, size: 16),
                label: const Text('Report a license violation'),
                onPressed: () => launchUrl(
                  Uri.parse('$repoUrl/issues'),
                  mode: LaunchMode.externalApplication,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
