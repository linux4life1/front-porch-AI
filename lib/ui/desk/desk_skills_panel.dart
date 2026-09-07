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

import 'package:front_porch_ai/services/desk/desk.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Official anthropics/skills catalog + installed list. HTTPS install,
/// no git clone.
class DeskSkillsPanel extends StatefulWidget {
  const DeskSkillsPanel({super.key, required this.hub, this.onChanged});

  final DeskSkillHub hub;
  final VoidCallback? onChanged;

  @override
  State<DeskSkillsPanel> createState() => _DeskSkillsPanelState();
}

class _DeskSkillsPanelState extends State<DeskSkillsPanel> {
  var _busy = false;
  String _flash = '';

  DeskSkillHub get _hub => widget.hub;

  @override
  void initState() {
    super.initState();
    _hub.refreshLocal().then((_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _refresh() async {
    setState(() => _busy = true);
    await _hub.refreshLocal();
    await _hub.refreshMarket();
    if (!mounted) return;
    setState(() => _busy = false);
    widget.onChanged?.call();
  }

  Future<void> _install(String name) async {
    setState(() => _busy = true);
    final out = await _hub.install(name);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _flash = out;
    });
    widget.onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    final amber = AppColors.porchAmberOf(context);
    final secondary = AppColors.textSecondary(context);
    final n = _hub.market.catalog.length;
    return Padding(
      key: const Key('desk-skills-panel'),
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            n == 0
                ? 'Allowlisted catalogs: Anthropic, Vercel, Superpowers. '
                      'HTTPS only — tap Refresh. Random GitHub is not a store.'
                : '$n skills from Anthropic, Vercel, and Superpowers. '
                      'Allowlisted HTTPS catalogs only.',
            style: TextStyle(fontSize: 11, height: 1.35, color: secondary),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 2),
            child: Text(
              _hub.destDir,
              key: const Key('desk-skills-folder'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, height: 1.35, color: secondary),
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const Key('desk-skills-refresh'),
              onPressed: _busy ? null : _refresh,
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              icon: _busy
                  ? SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: amber,
                      ),
                    )
                  : Icon(Icons.refresh, size: 14, color: amber),
              label: Text(
                'Refresh',
                style: TextStyle(fontSize: 12, color: amber),
              ),
            ),
          ),
          if (_hub.error.isNotEmpty)
            Text(_hub.error, style: TextStyle(fontSize: 11, color: secondary)),
          if (_flash.isNotEmpty)
            Text(
              _flash,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: amber),
            ),
          _names(context, 'Installed', [
            for (final s in _hub.porchInstalled) s.name,
          ], empty: 'none yet'),
          if (_hub.diskInstalled.isNotEmpty)
            _names(context, 'Also on disk', [
              for (final s in _hub.diskInstalled) s.name,
            ]),
          const SizedBox(height: 8),
          for (final src in kDeskSkillSources) ...[
            Text(
              src.label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary(context),
              ),
            ),
            for (final s in _hub.market.catalog)
              if (s.sourceId == src.id) _row(context, s, amber),
            const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }

  Widget _names(
    BuildContext context,
    String title,
    List<String> names, {
    String? empty,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary(context),
            ),
          ),
          const SizedBox(height: 4),
          if (names.isEmpty)
            Text(
              empty ?? 'none',
              style: TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary(context),
              ),
            )
          else
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final name in names)
                  Text(
                    name,
                    key: Key('desk-skill-installed-$name'),
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary(context),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, DeskMarketSkill s, Color amber) {
    final on = _hub.installedNames.contains(s.name);
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              s.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textPrimary(context),
              ),
            ),
          ),
          if (on)
            Text('On', style: TextStyle(fontSize: 11, color: amber))
          else
            TextButton(
              key: Key('desk-skill-install-${s.name}'),
              onPressed: _busy ? null : () => _install(s.name),
              style: TextButton.styleFrom(
                foregroundColor: amber,
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: Size.zero,
              ),
              child: const Text(
                'Install',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ),
        ],
      ),
    );
  }
}
