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

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

import 'porch_life_defaults_note.dart';
import 'porch_life_engine_card.dart';
import 'porch_life_groups.dart';
import 'porch_life_mcp_web_card.dart';
import 'porch_life_memory_group.dart';

/// **Porch Life** — every "what makes characters feel alive" switch in one
/// place, grouped by what it is, nested by subgroup dependencies.
///
/// Groups and detailed row descriptions start expanded and can be collapsed
/// individually (group header / row title or subtitle) or via the top-bar
/// Collapse/Expand all details button. On wide windows (`>= 960px`), cards
/// arrange into two balanced columns to keep reading widths comfortable.
class PorchLifeTab extends StatefulWidget {
  const PorchLifeTab({super.key});

  @override
  State<PorchLifeTab> createState() => _PorchLifeTabState();
}

class _PorchLifeTabState extends State<PorchLifeTab> {
  int _detailsVersion = 0;
  bool _detailsAllExpanded = true;

  final Map<String, GlobalKey> _rowKeys = {};
  final Map<String, int> _forceExpandVersions = {};
  String? _highlightedId;
  Timer? _highlightTimer;

  GlobalKey _rowKeyFor(String id) =>
      _rowKeys.putIfAbsent(id, () => GlobalKey());

  static const _targetGroup = {
    'realism': 'engine',
    'needs': 'engine',
    'passage_of_time': 'time',
    'story_weather': 'time',
    'journal': 'memory',
    'pockets': 'memory',
    'objectives': 'memory',
  };

  @override
  void dispose() {
    _highlightTimer?.cancel();
    super.dispose();
  }

  void _toggleAllDetails() {
    setState(() {
      _detailsAllExpanded = !_detailsAllExpanded;
      _detailsVersion++;
    });
  }

  void _jumpTo(String targetId) {
    final group = _targetGroup[targetId];
    setState(() {
      if (group != null) {
        _forceExpandVersions[group] = (_forceExpandVersions[group] ?? 0) + 1;
      }
      _highlightedId = targetId;
    });
    _highlightTimer?.cancel();
    _highlightTimer = Timer(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _highlightedId = null);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ctx = _rowKeys[targetId]?.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          alignment: 0.2,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final storage = context.watch<StorageService>();
    final engineOn = storage.realismSettings.realismAllowed;
    final adultOn = storage.realismSettings.adultThemesEnabled;

    final detailsSignal = (
      version: _detailsVersion,
      expanded: _detailsAllExpanded,
    );

    final engineCard = PorchLifeEngineCard(
      engineOn: engineOn,
      storage: storage,
      expandDetailsSignal: detailsSignal,
      forceExpandVersion: _forceExpandVersions['engine'] ?? 0,
      realismKey: _rowKeyFor('realism'),
      needsKey: _rowKeyFor('needs'),
      highlightedId: _highlightedId,
      onJumpTo: _jumpTo,
    );

    final timeCard = PorchLifeTimeGroup(
      storage: storage,
      expandDetailsSignal: detailsSignal,
      forceExpandVersion: _forceExpandVersions['time'] ?? 0,
      highlightedId: _highlightedId,
      rowKeyFor: _rowKeyFor,
      onJumpTo: _jumpTo,
    );

    final memoryCard = PorchLifeMemoryGroup(
      storage: storage,
      expandDetailsSignal: detailsSignal,
      forceExpandVersion: _forceExpandVersions['memory'] ?? 0,
      highlightedId: _highlightedId,
      rowKeyFor: _rowKeyFor,
      onJumpTo: _jumpTo,
    );

    final presenceCard = PorchLifePresenceGroup(
      storage: storage,
      expandDetailsSignal: detailsSignal,
    );

    final toolsCard = PorchLifeMcpWebCard(expandDetailsSignal: detailsSignal);

    final afterDarkCard = adultOn
        ? PorchLifeAfterDarkGroup(
            storage: storage,
            engineOn: engineOn,
            expandDetailsSignal: detailsSignal,
            onJumpTo: _jumpTo,
          )
        : null;

    return LayoutBuilder(
      builder: (context, constraints) {
        final twoColumns = constraints.maxWidth >= 960;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _PorchLifeHeaderBar(
              detailsExpanded: _detailsAllExpanded,
              onToggleDetails: _toggleAllDetails,
            ),
            const SizedBox(height: 16),
            if (twoColumns)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [engineCard, timeCard, toolsCard],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [memoryCard, presenceCard, ?afterDarkCard],
                    ),
                  ),
                ],
              )
            else ...[
              engineCard,
              timeCard,
              memoryCard,
              presenceCard,
              toolsCard,
              ?afterDarkCard,
            ],
            const PorchLifeDefaultsNote(),
          ],
        );
      },
    );
  }
}

class _PorchLifeHeaderBar extends StatelessWidget {
  const _PorchLifeHeaderBar({
    required this.detailsExpanded,
    required this.onToggleDetails,
  });

  final bool detailsExpanded;
  final VoidCallback onToggleDetails;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 10,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Text(
            'Everything that makes a character feel like they live somewhere. '
            'Click any group to collapse it, or click an item title to toggle '
            'its explanation.',
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              color: AppColors.textSecondary(context),
            ),
          ),
        ),
        OutlinedButton.icon(
          onPressed: onToggleDetails,
          icon: Icon(
            detailsExpanded ? Icons.notes_outlined : Icons.subject_outlined,
            size: 16,
          ),
          label: Text(
            detailsExpanded ? 'Collapse all details' : 'Expand all details',
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.textPrimary(context),
            side: BorderSide(color: AppColors.borderOf(context)),
            backgroundColor: AppColors.cardOf(context),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            textStyle: Theme.of(context).textTheme.labelMedium?.copyWith(
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
