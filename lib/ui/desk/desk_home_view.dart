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

import 'package:front_porch_ai/services/desk/desk.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/desk/desk_page.dart';
import 'package:front_porch_ai/ui/desk/desk_wizard_page.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Third home pane — sibling of Chats and Porch Stories. Sit down opens
/// the Project → Coworker → Sit down wizard. Separate pipeline from chat.
class DeskHomeView extends StatefulWidget {
  const DeskHomeView({
    super.key,
    this.onSitDown,
    this.lastSession,
    this.onResume,
    this.store,
  });

  /// Test seam. Production navigates to [DeskWizardPage].
  final VoidCallback? onSitDown;
  final DeskSession? lastSession;
  final VoidCallback? onResume;

  /// Test seam. Production reads [StorageService.rootPath]/desk.
  final DeskStore? store;

  @override
  State<DeskHomeView> createState() => _DeskHomeViewState();
}

class _DeskHomeViewState extends State<DeskHomeView> {
  DeskSession? _stored;
  var _routeCurrent = false;

  DeskSession? get _last => widget.lastSession ?? _stored;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.lastSession != null) return;
    final current = ModalRoute.of(context)?.isCurrent ?? true;
    if (current && !_routeCurrent) _load();
    _routeCurrent = current;
  }

  Future<void> _load() async {
    final store = _storeOf();
    if (store == null) return;
    final last = await store.loadLast();
    if (!mounted) return;
    setState(() => _stored = last);
  }

  DeskStore? _storeOf() {
    if (widget.store != null) return widget.store;
    try {
      final storage = Provider.of<StorageService>(context, listen: false);
      final root = storage.rootPath;
      if (root == null || root.isEmpty) return null;
      return DeskStore(deskStoreDirectory(root));
    } catch (_) {
      return null;
    }
  }

  void _openWizard() {
    var local = false;
    var label = '';
    try {
      final llm = Provider.of<LLMProvider>(context, listen: false);
      local = llm.isLocal;
      label = local ? 'local Kobold' : 'remote';
    } catch (_) {}
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            DeskWizardPage(isLocalBackend: local, backendLabel: label),
      ),
    );
  }

  void _resume() {
    final last = _last;
    if (last == null) return;
    if (widget.onResume != null) {
      widget.onResume!();
      return;
    }
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => DeskPage(session: last)));
  }

  @override
  Widget build(BuildContext context) {
    final last = _last;
    final amber = AppColors.porchAmberOf(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.desk, size: 72, color: amber.withValues(alpha: 0.4)),
            const SizedBox(height: 24),
            Text(
              'Desk',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: AppColors.textPrimary(context),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Pick a throwaway folder and a coworker. She codes in character.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: AppColors.textSecondary(context),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              key: const Key('desk-sit-down'),
              onPressed: widget.onSitDown ?? _openWizard,
              icon: const Icon(Icons.chair_alt, size: 20),
              label: const Text('Sit down'),
              style: ElevatedButton.styleFrom(
                backgroundColor: amber,
                foregroundColor: AppColors.onChaosAccent,
              ),
            ),
            if (last != null) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: const Key('desk-resume'),
                onPressed: _resume,
                icon: const Icon(Icons.replay, size: 20),
                label: Text(
                  last.title.isEmpty
                      ? 'Resume ${last.coworker.name}'
                      : 'Resume ${last.title}',
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: amber,
                  side: BorderSide(color: amber),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
