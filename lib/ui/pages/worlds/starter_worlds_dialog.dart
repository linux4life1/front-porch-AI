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
//
// The Worlds page's "Starter worlds" picker: the bundled example worlds
// with a one-line blurb, climate and place count, and an Add per world.
// The web twin is web_ui/src/components/StarterWorldsPicker.tsx.

import 'package:flutter/material.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

/// Open the starter-world picker over the Worlds page. [starters] is for
/// tests; the page passes nothing and gets the bundled set over [repo].
Future<void> showStarterWorldsDialog(
  BuildContext context,
  WorldRepository repo, {
  StarterWorlds? starters,
}) => showWarmDialogOf<void>(
  context,
  builder: (_) =>
      StarterWorldsDialog(starters: starters ?? StarterWorlds(repo)),
);

/// The picker body; adds go through [StarterWorlds.add], so each one lands
/// as an ordinary root with its places, editable and deletable.
class StarterWorldsDialog extends StatefulWidget {
  const StarterWorldsDialog({super.key, required this.starters});

  final StarterWorlds starters;

  @override
  State<StarterWorldsDialog> createState() => _StarterWorldsDialogState();
}

class _StarterWorldsDialogState extends State<StarterWorldsDialog> {
  late final Future<List<StarterWorldInfo>> _index = widget.starters.index();

  /// Ids being added. Checked and set before the first await, so a second
  /// click that lands before the rebuild is a no-op.
  final Set<String> _busy = {};

  /// Id → name of the root this dialog just added (names can be numbered
  /// when the world is already in the library).
  final Map<String, String> _added = {};
  final Map<String, String> _failed = {};

  Future<void> _add(StarterWorldInfo info) async {
    if (!_busy.add(info.id)) return;
    setState(() => _failed.remove(info.id));
    try {
      final root = await widget.starters.add(info.id);
      if (mounted) setState(() => _added[info.id] = root.name);
    } catch (e) {
      debugPrint('starter world ${info.id}: add failed: $e');
      if (mounted) setState(() => _failed[info.id] = 'Could not add: $e');
    } finally {
      _busy.remove(info.id);
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return WarmDialog(
      title: 'Starter worlds',
      icon: Icons.travel_explore,
      accent: AppColors.formAccentOf(context),
      width: 480,
      content: FutureBuilder<List<StarterWorldInfo>>(
        future: _index,
        builder: (context, snap) {
          if (snap.hasError) {
            return Text(
              'The starter worlds could not be read: ${snap.error}',
              style: TextStyle(color: AppColors.negativeAccentOf(context)),
            );
          }
          final rows = snap.data;
          if (rows == null) {
            return const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          return SingleChildScrollView(
            key: const Key('starter-worlds-list'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Example worlds with places inside them, to try climates, '
                  'places and the Ambient Stage. Each one is added as an '
                  'ordinary world you can edit or delete.',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary(context),
                  ),
                ),
                for (final info in rows) ...[
                  const SizedBox(height: 12),
                  _StarterRow(
                    info: info,
                    busy: _busy.contains(info.id),
                    addedAs: _added[info.id],
                    inLibrary: widget.starters.isAdded(info.id),
                    error: _failed[info.id],
                    onAdd: () => _add(info),
                  ),
                ],
              ],
            ),
          );
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _StarterRow extends StatelessWidget {
  const _StarterRow({
    required this.info,
    required this.busy,
    required this.addedAs,
    required this.inLibrary,
    required this.error,
    required this.onAdd,
  });

  final StarterWorldInfo info;
  final bool busy;
  final String? addedAs;
  final bool inLibrary;
  final String? error;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.formAccentOf(context);
    final status =
        error ??
        (addedAs != null
            ? 'Added as "$addedAs".'
            : inLibrary
            ? 'Already in your library.'
            : null);
    return Container(
      key: Key('starter-row-${info.id}'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: InkColors.washOf(context, 0.05, 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            info.name,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary(context),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            info.blurb,
            style: TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary(context),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _Chip(
                icon: Icons.thermostat,
                label: info.customClimate
                    ? '${info.climate} (custom climate)'
                    : info.climate,
              ),
              _Chip(
                icon: Icons.place_outlined,
                label: '${info.places} place${info.places == 1 ? '' : 's'}',
              ),
              if (info.ownClimates > 0)
                _Chip(
                  icon: Icons.wb_sunny_outlined,
                  label:
                      '${info.ownClimates} with '
                      '${info.ownClimates == 1 ? 'its' : 'their'} own climate',
                ),
              if (info.loreEntries > 0)
                _Chip(
                  icon: Icons.library_books,
                  label: '${info.loreEntries} lore entries',
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: status == null
                    ? const SizedBox.shrink()
                    : Text(
                        status,
                        style: TextStyle(
                          fontSize: 12,
                          color: error != null
                              ? AppColors.negativeAccentOf(context)
                              : AppColors.textTertiary(context),
                        ),
                      ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                key: Key('starter-add-${info.id}'),
                icon: busy
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.add, size: 18),
                label: Text(addedAs != null || inLibrary ? 'Add again' : 'Add'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: AppColors.onAccentOf(context),
                ),
                onPressed: busy ? null : onAdd,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: InkColors.washOf(context, 0.05, 0.04),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: InkColors.chipEdgeOf(context)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: AppColors.textTertiary(context)),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: AppColors.textTertiary(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
