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

import 'package:front_porch_ai/ui/settings/tabs/general_tab/general_tab.dart';
import 'package:front_porch_ai/ui/settings/widgets/widgets.dart';

/// Settings → General.
///
/// Reorganized into 4 card-contained categories:
/// 1. Application & System (updates, spellcheck, 18+ themes)
/// 2. Chat Behavior & Display (message alignment, follow streaming)
/// 3. Default Prompts & Instructions (1:1 fallback, group, global additions)
/// 4. About & License (app version, AGPL-3.0 notice, repo links)
///
/// Pinned Parity Markers (docs/design/settings-parity-manifest.json):
/// - "My messages on the right" -> ChatBehaviorSection
/// - "Follow streaming replies" -> ChatBehaviorSection
/// - "SpellCheckLanguageRow" -> AppSystemSection
/// - "Fallback system prompt" -> PromptsSection
/// - "Porch Life" -> AppSystemSection (18+ themes switch)
/// - "About & License" -> AboutLicenseCard
class GeneralTab extends StatelessWidget {
  const GeneralTab({super.key, required this.systemPromptController});

  final TextEditingController systemPromptController;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppSystemSection(),
          const SizedBox(height: 28),
          const ChatBehaviorSection(),
          const SizedBox(height: 28),
          PromptsSection(systemPromptController: systemPromptController),
          const SizedBox(height: 28),
          const SectionHeader('About & License'),
          const SizedBox(height: 12),
          const AboutLicenseCard(),
        ],
      ),
    );
  }
}
