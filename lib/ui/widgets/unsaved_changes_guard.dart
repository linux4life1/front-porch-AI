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

import 'package:front_porch_ai/ui/widgets/warm_dialog.dart';

/// Every live [UnsavedChangesGuard]. Ways out that are not a route pop (a
/// sidebar tab switch, closing the window) ask here before they throw a page
/// away.
class UnsavedChanges {
  UnsavedChanges._();
  static final instance = UnsavedChanges._();

  final List<_UnsavedChangesGuardState> _guards = [];

  bool get hasUnsaved => _guards.any((g) => g.mounted && g.widget.isDirty());

  /// True when nothing is unsaved or the user chose Discard. [context] is
  /// where the question is shown; without one it is shown over the first
  /// dirty guard.
  /// A second request while the question is up (the close button clicked
  /// twice) answers false instead of stacking another dialog.
  Future<bool> confirmLeave([BuildContext? context]) async {
    final dirty = _guards.where((g) => g.mounted && g.widget.isDirty());
    if (dirty.isEmpty) return true;
    if (_asking) return false;
    final at = context != null && context.mounted
        ? context
        : dirty.first.context;
    _asking = true;
    try {
      return await confirmDiscardChanges(at);
    } finally {
      _asking = false;
    }
  }

  bool _asking = false;
}

/// Asks before edits are thrown away. True means Discard.
Future<bool> confirmDiscardChanges(BuildContext context) async {
  final discard = await showWarmDialogOf<bool>(
    context,
    builder: (ctx) => WarmDialog(
      title: 'Discard unsaved changes?',
      icon: Icons.warning_amber_rounded,
      destructive: true,
      content: const WarmDialogText(
        'You have edits that have not been saved. If you leave now they '
        'will be lost.',
      ),
      actions: [
        warmDialogCancel(ctx, label: 'Keep editing', value: false),
        warmDialogConfirm(
          ctx,
          key: const ValueKey('unsaved-discard'),
          label: 'Discard',
          destructive: true,
          onPressed: () => Navigator.of(ctx).pop(true),
        ),
      ],
    ),
  );
  return discard == true;
}

/// Wrap a page or dialog whose edits are only written by an explicit Save.
/// While [isDirty] is true, back (button, gesture, Escape, a barrier tap or
/// any `maybePop`) asks before leaving, and so do the sidebar and the window
/// close button through [UnsavedChanges]. [isDirty] is read at the moment
/// the user tries to leave, so edits that never call `setState` count too.
///
/// A leave button must use `Navigator.maybePop`; `Navigator.pop` skips the
/// guard on purpose, which is how Save leaves after it has written.
class UnsavedChangesGuard extends StatefulWidget {
  const UnsavedChangesGuard({
    super.key,
    required this.isDirty,
    required this.child,
  });

  final ValueGetter<bool> isDirty;
  final Widget child;

  @override
  State<UnsavedChangesGuard> createState() => _UnsavedChangesGuardState();
}

class _UnsavedChangesGuardState extends State<UnsavedChangesGuard> {
  @override
  void initState() {
    super.initState();
    UnsavedChanges.instance._guards.add(this);
  }

  @override
  void dispose() {
    UnsavedChanges.instance._guards.remove(this);
    super.dispose();
  }

  /// Every pop is held here so dirtiness is checked live, not as of the last
  /// build.
  Future<void> _onPop(bool didPop, Object? result) async {
    if (didPop) return;
    final navigator = Navigator.of(context);
    final route = ModalRoute.of(context);
    if (widget.isDirty() && !await confirmDiscardChanges(context)) return;
    if (!mounted) return;
    // The root page has nowhere to go back to; the sidebar handles leaving it.
    if (route != null && route.isCurrent && navigator.canPop()) {
      navigator.pop(result);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope<Object?>(
    canPop: false,
    onPopInvokedWithResult: _onPop,
    child: widget.child,
  );
}
