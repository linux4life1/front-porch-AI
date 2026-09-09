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

import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Main-stage Plan panel: open the active `.waifu/plans/*.md`, Accept → Build,
/// Revise back to Plan, or Discard the pin. Not a mode chip.
class WaifuPlanPanel extends StatefulWidget {
  WaifuPlanPanel({
    super.key,
    required this.session,
    this.harness,
    this.onChanged,
    this.initialPlan,
  }) : pinnedPath = session.activePlanPath,
       lastWritePath = session.lastWrite?.relativePath;

  final WaifuSession session;
  final WaifuHarness? harness;
  final VoidCallback? onChanged;

  /// Test / first-frame seam: skip the post-frame disk load when the
  /// caller already has the plan. Accept still goes through the harness.
  final WaifuPlan? initialPlan;

  /// Copied at build so [didUpdateWidget] can see in-place session
  /// mutations (the session object itself does not change identity).
  final String? pinnedPath;
  final String? lastWritePath;

  @override
  State<WaifuPlanPanel> createState() => _WaifuPlanPanelState();
}

class _WaifuPlanPanelState extends State<WaifuPlanPanel> {
  final _body = TextEditingController();
  WaifuPlan? _plan;
  var _busy = false;
  String _flash = '';

  @override
  void initState() {
    super.initState();
    final seeded = widget.initialPlan;
    if (seeded != null) {
      _plan = seeded;
      _body.text = waifuPlanEncode(seeded);
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _reload();
      });
    }
  }

  @override
  void didUpdateWidget(covariant WaifuPlanPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (waifuPlanPanelShouldReload(
      previousPin: oldWidget.pinnedPath,
      nextPin: widget.pinnedPath,
      previousWrite: oldWidget.lastWritePath,
      nextWrite: widget.lastWritePath,
      previousMode: oldWidget.session.mode,
      nextMode: widget.session.mode,
    )) {
      _reload();
    }
  }

  @override
  void dispose() {
    _body.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final plan = await waifuLoadActivePlan(widget.session);
    if (!mounted) return;
    setState(() {
      _plan = plan;
      if (plan != null) _body.text = waifuPlanEncode(plan);
    });
  }

  Future<void> _run(Future<void> Function() fn, String ok) async {
    setState(() {
      _busy = true;
      _flash = '';
    });
    var succeeded = false;
    var failed = false;
    try {
      await fn();
      if (!mounted) return;
      await _reload();
      if (!mounted) return;
      succeeded = true;
      widget.onChanged?.call();
    } catch (_) {
      failed = true;
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          if (succeeded) _flash = ok;
          if (failed) _flash = 'Could not apply.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final amber = AppColors.porchAmberOf(context);
    final secondary = AppColors.textSecondary(context);
    final plan = _plan;
    return LayoutBuilder(
      builder: (context, constraints) {
        final pinActions = constraints.maxHeight.isFinite;
        return Padding(
          key: const Key('waifu-plan-panel'),
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                plan == null
                    ? 'No plan file yet. Stay in Plan and ask them to write '
                          '$kWaifuPlansDir/<slug>.md — that folder is hidden '
                          '(it starts with a dot; Finder: Cmd+Shift+., terminal: '
                          'ls -a). Project source stays read-only.'
                    : '${plan.title} · ${plan.status.name}',
                key: const Key('waifu-plan-title'),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary(context),
                ),
              ),
              if (plan != null && plan.goal.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    plan.goal,
                    style: TextStyle(fontSize: 12, color: secondary),
                  ),
                ),
              if (plan != null && !pinActions && plan.steps.isNotEmpty) ...[
                const SizedBox(height: 8),
                for (final step in plan.steps)
                  Text(
                    '${step.id} [${step.status}] ${step.title}',
                    style: TextStyle(fontSize: 12, color: secondary),
                  ),
              ],
              if (plan != null) ...[
                const SizedBox(height: 8),
                if (pinActions)
                  Expanded(child: _editor(context, amber, expands: true))
                else
                  _editor(context, amber, expands: false),
                const SizedBox(height: 8),
                _actions(amber),
              ],
              if (_flash.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    _flash,
                    style: TextStyle(fontSize: 11, color: amber),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _editor(BuildContext context, Color amber, {required bool expands}) {
    return TextField(
      key: const Key('waifu-plan-body'),
      controller: _body,
      minLines: expands ? null : 6,
      maxLines: expands ? null : 16,
      expands: expands,
      textAlignVertical: TextAlignVertical.top,
      enabled: !_busy,
      style: TextStyle(fontSize: 12, color: AppColors.textPrimary(context)),
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: AppColors.surfaceContainerOf(context),
        border: OutlineInputBorder(
          borderSide: BorderSide(color: amber.withValues(alpha: 0.35)),
        ),
      ),
    );
  }

  Widget _actions(Color amber) {
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        FilledButton(
          key: const Key('waifu-plan-accept'),
          onPressed: _busy
              ? null
              : () {
                  final h = widget.harness;
                  if (h == null) {
                    setState(() => _flash = 'Could not apply.');
                    return;
                  }
                  unawaited(
                    _run(() async {
                      final next = await h.acceptActivePlan(
                        editedBody: _body.text,
                      );
                      if (next == null) {
                        throw Exception('accept returned null');
                      }
                    }, 'Accepted — Build'),
                  );
                },
          style: FilledButton.styleFrom(
            backgroundColor: amber,
            foregroundColor: AppColors.onChaosAccent,
            visualDensity: VisualDensity.compact,
          ),
          child: const Text('Accept → Build'),
        ),
        OutlinedButton(
          key: const Key('waifu-plan-revise'),
          onPressed: _busy
              ? null
              : () {
                  final h = widget.harness;
                  if (h == null) {
                    setState(() => _flash = 'Could not apply.');
                    return;
                  }
                  unawaited(
                    _run(
                      () => h.reviseActivePlan(editedBody: _body.text),
                      'Back to Plan',
                    ),
                  );
                },
          child: const Text('Revise'),
        ),
        TextButton(
          key: const Key('waifu-plan-discard'),
          onPressed: _busy
              ? null
              : () {
                  final h = widget.harness;
                  if (h == null) {
                    setState(() => _flash = 'Could not apply.');
                    return;
                  }
                  unawaited(_run(h.discardActivePlan, 'Pin cleared'));
                },
          child: const Text('Discard'),
        ),
      ],
    );
  }
}
