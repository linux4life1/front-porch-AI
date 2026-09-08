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

import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Sidebar Plan panel: open the active `.waifu/plans/*.md`, Accept → Build,
/// Revise back to Plan, or Discard the pin. Not a mode chip.
class WaifuPlanPanel extends StatefulWidget {
  const WaifuPlanPanel({
    super.key,
    required this.session,
    this.harness,
    this.onChanged,
  });

  final WaifuSession session;
  final WaifuHarness? harness;
  final VoidCallback? onChanged;

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
    _reload();
  }

  @override
  void didUpdateWidget(covariant WaifuPlanPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session.activePlanPath != widget.session.activePlanPath ||
        oldWidget.session.mode != widget.session.mode) {
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
    await fn();
    if (!mounted) return;
    await _reload();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _flash = ok;
    });
    widget.onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    final amber = AppColors.porchAmberOf(context);
    final secondary = AppColors.textSecondary(context);
    final plan = _plan;
    return Padding(
      key: const Key('waifu-plan-panel'),
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            plan == null
                ? 'No plan file yet. Stay in Plan and ask them to write '
                      '$kWaifuPlansDir/<slug>.md. Project source stays read-only.'
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
          if (plan != null && plan.steps.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final step in plan.steps)
              Text(
                '${step.id} [${step.status}] ${step.title}',
                style: TextStyle(fontSize: 12, color: secondary),
              ),
          ],
          if (plan != null) ...[
            const SizedBox(height: 8),
            TextField(
              key: const Key('waifu-plan-body'),
              controller: _body,
              minLines: 6,
              maxLines: 16,
              enabled: !_busy,
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textPrimary(context),
              ),
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: AppColors.cardOf(context),
                border: OutlineInputBorder(
                  borderSide: BorderSide(color: amber.withValues(alpha: 0.35)),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                FilledButton(
                  key: const Key('waifu-plan-accept'),
                  onPressed: _busy
                      ? null
                      : () => _run(() async {
                          await widget.harness?.acceptActivePlan(
                            editedBody: _body.text,
                          );
                        }, 'Accepted — Build'),
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
                      : () => _run(() async {
                          await widget.harness?.reviseActivePlan(
                            editedBody: _body.text,
                          );
                        }, 'Back to Plan'),
                  child: const Text('Revise'),
                ),
                TextButton(
                  key: const Key('waifu-plan-discard'),
                  onPressed: _busy
                      ? null
                      : () => _run(() async {
                          await widget.harness?.discardActivePlan();
                        }, 'Pin cleared'),
                  child: const Text('Discard'),
                ),
              ],
            ),
          ],
          if (_flash.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(_flash, style: TextStyle(fontSize: 11, color: amber)),
            ),
        ],
      ),
    );
  }
}
