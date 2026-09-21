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

import 'package:front_porch_ai/services/image/image.dart';
import 'package:front_porch_ai/services/storage/settings/remote_api_key_vault.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Nano-GPT / OpenRouter chips for Image Studio Remote API.
///
/// A chip is tappable only when [keyFor] that host is non-empty; otherwise
/// it stays disabled with a Settings → Backend hint.
class RemoteImageHostChips extends StatelessWidget {
  const RemoteImageHostChips({
    super.key,
    required this.selectedUrl,
    required this.keyFor,
    required this.onSelect,
  });

  final String selectedUrl;
  final String Function(String url) keyFor;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final selected = normalizeRemoteApiUrl(selectedUrl);
    final missing = [
      for (final h in kImageStudioRemoteHosts)
        if (keyFor(h.url).isEmpty) h.label,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            for (var i = 0; i < kImageStudioRemoteHosts.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(
                child: _HostChip(
                  host: kImageStudioRemoteHosts[i],
                  selected:
                      selected.isNotEmpty &&
                      normalizeRemoteApiUrl(kImageStudioRemoteHosts[i].url) ==
                          selected,
                  hasKey: keyFor(kImageStudioRemoteHosts[i].url).isNotEmpty,
                  onSelect: onSelect,
                ),
              ),
            ],
          ],
        ),
        if (missing.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            '${missing.join(' / ')}: add a key in Settings → Backend.',
            style: TextStyle(
              color: AppColors.textTertiary(context),
              fontSize: 11,
            ),
          ),
        ],
      ],
    );
  }
}

class _HostChip extends StatelessWidget {
  const _HostChip({
    required this.host,
    required this.selected,
    required this.hasKey,
    required this.onSelect,
  });

  final ImageStudioRemoteHost host;
  final bool selected;
  final bool hasKey;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.porchAmberOf(context);
    final enabled = hasKey;
    final bg = !enabled
        ? AppColors.surfaceContainerOf(context).withValues(alpha: 0.5)
        : selected
        ? accent
        : AppColors.surfaceContainerOf(context);
    final fg = !enabled
        ? AppColors.textTertiary(context)
        : selected
        ? AppColors.onChaosAccent
        : AppColors.textSecondary(context);
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        key: Key('image-remote-host-${host.id}'),
        onTap: enabled ? () => onSelect(host.url) : null,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected && enabled ? accent : AppColors.borderOf(context),
            ),
          ),
          child: Text(
            host.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              height: 1.1,
              color: fg,
            ),
          ),
        ),
      ),
    );
  }
}
