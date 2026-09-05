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

/// Full catalog as toggles. Off = nothing fetched. None start ticked.
class DeskLanguageHelp extends StatefulWidget {
  const DeskLanguageHelp({
    super.key,
    required this.langs,
    this.suggested = const {},
  });

  final DeskLangRuntime langs;
  final Set<String> suggested;

  @override
  State<DeskLanguageHelp> createState() => _DeskLanguageHelpState();
}

class _DeskLanguageHelpState extends State<DeskLanguageHelp> {
  final _search = TextEditingController();
  final _command = TextEditingController();
  final _args = TextEditingController();
  final _exts = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    _command.dispose();
    _args.dispose();
    _exts.dispose();
    super.dispose();
  }

  List<DeskLangDoor> get _visible {
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return widget.langs.catalog;
    return [
      for (final d in widget.langs.catalog)
        if (d.name.toLowerCase().contains(q) || d.id.contains(q)) d,
    ];
  }

  Future<void> _toggle(DeskLangDoor door, bool on) async {
    if (on) {
      await widget.langs.enable(door.id);
    } else {
      await widget.langs.disable(door.id);
    }
    if (mounted) setState(() {});
  }

  void _addCustom() {
    final command = _command.text.trim();
    if (command.isEmpty) return;
    final id = command.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    widget.langs.addCustom(
      id: id,
      command: command,
      args: _args.text
          .trim()
          .split(RegExp(r'\s+'))
          .where((s) => s.isNotEmpty)
          .toList(),
      extensions: _exts.text
          .trim()
          .split(RegExp(r'[\s,]+'))
          .where((s) => s.isNotEmpty)
          .toList(),
    );
    _command.clear();
    _args.clear();
    _exts.clear();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final amber = AppColors.porchAmberOf(context);
    return Scaffold(
      backgroundColor: AppColors.backgroundOf(context),
      appBar: AppBar(
        backgroundColor: AppColors.surfaceOf(context),
        title: Text(
          'Language help',
          style: TextStyle(color: AppColors.textPrimary(context)),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              key: const Key('desk-lang-search'),
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Search languages',
                filled: true,
                fillColor: AppColors.surfaceContainerOf(context),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: [
                for (final door in _visible)
                  SwitchListTile(
                    key: Key('desk-lang-${door.id}'),
                    value: widget.langs.enabled.contains(door.id),
                    onChanged: (v) => _toggle(door, v),
                    activeThumbColor: amber,
                    title: Text(
                      door.name,
                      style: TextStyle(color: AppColors.textPrimary(context)),
                    ),
                    subtitle: Text(
                      widget.suggested.contains(door.id)
                          ? 'Detected in this folder — still off until you toggle'
                          : (door.pathCommand ??
                                'Bring your own binary — no download'),
                      style: TextStyle(
                        color: AppColors.textSecondary(context),
                        fontSize: 12,
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'Custom door',
                    style: TextStyle(color: AppColors.textPrimary(context)),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: TextField(
                    key: const Key('desk-lang-custom-command'),
                    controller: _command,
                    decoration: const InputDecoration(
                      hintText: 'Command to run',
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: TextField(
                    controller: _args,
                    decoration: const InputDecoration(
                      hintText: 'Args (optional)',
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: TextField(
                    controller: _exts,
                    decoration: const InputDecoration(
                      hintText: 'Extensions (.HC)',
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  child: ElevatedButton(
                    key: const Key('desk-lang-custom-add'),
                    onPressed: _addCustom,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: amber,
                      foregroundColor: AppColors.onChaosAccent,
                    ),
                    child: const Text('Add custom door'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
