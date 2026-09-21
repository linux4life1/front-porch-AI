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

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/storage/settings/web_search_settings.dart';
import 'package:front_porch_ai/ui/settings/widgets/widgets.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

import 'porch_accordion.dart';

/// Chat-sidebar wiki picker. Porch Life is the library; this only selects
/// which saved wiki this chat uses (or none).
class WikiPanel extends StatelessWidget {
  const WikiPanel({
    super.key,
    required this.chatService,
    required this.initiallyExpanded,
    this.onExpansionChanged,
  });

  final ChatService chatService;
  final bool initiallyExpanded;
  final ValueChanged<bool>? onExpansionChanged;

  @override
  Widget build(BuildContext context) {
    final storage = context.watch<StorageService>();
    final chat = chatService;
    final current = chat.wikiBaseUrl;
    final urls = storage.webSearchSettings.pickerWikiUrls(current: current);
    if (urls.isEmpty && current.trim().isEmpty) {
      return const SizedBox.shrink();
    }
    final selected = canonicalizeWikiUrl(current) ?? '';
    final subtitle = selected.isEmpty ? 'off' : wikiHostLabel(selected);
    return PorchAccordion(
      id: 'wiki',
      emoji: '📖',
      title: 'Wiki',
      subtitle: subtitle,
      accent: AppColors.porchAmberOf(context),
      initiallyExpanded: initiallyExpanded,
      onExpansionChanged: onExpansionChanged,
      child: Column(
        key: const Key('wiki-picker'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            kWikiUrlBlurb,
            style: TextStyle(
              fontSize: 12,
              height: 1.35,
              color: AppColors.textSecondary(context),
            ),
          ),
          const SizedBox(height: 8),
          _WikiChoice(
            label: 'None (off for this chat)',
            selected: selected.isEmpty,
            onTap: () => chat.setWikiBaseUrl(''),
          ),
          for (final url in urls)
            _WikiChoice(
              label: wikiHostLabel(url),
              selected: selected == url,
              onTap: () => chat.setWikiBaseUrl(url),
            ),
        ],
      ),
    );
  }
}

class _WikiChoice extends StatelessWidget {
  const _WikiChoice({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final amber = AppColors.porchAmberOf(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              size: 18,
              color: selected ? amber : AppColors.iconSecondary(context),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textPrimary(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
