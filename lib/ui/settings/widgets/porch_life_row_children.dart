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

import 'package:front_porch_ai/services/chat/chat.dart' show ChaosFrequency;
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

// Sub-controls that ride inside a FeatureRow's `child` or `trailing` slot on
// the Porch Life tab.

/// Two-segment control for sidebar weather units (°C default / °F).
class TemperatureUnitControl extends StatelessWidget {
  const TemperatureUnitControl({
    super.key,
    required this.fahrenheit,
    required this.onChanged,
  });

  final bool fahrenheit;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.porchAmberOf(context);
    final surface = AppColors.surfaceContainerOf(context);
    final border = AppColors.borderOf(context);

    Widget segment(String label, bool targetValue) {
      final selected = fahrenheit == targetValue;
      return Semantics(
        button: true,
        enabled: onChanged != null,
        selected: selected,
        label: targetValue ? 'Fahrenheit' : 'Celsius',
        child: InkWell(
          onTap: onChanged == null ? null : () => onChanged!(targetValue),
          borderRadius: BorderRadius.circular(7),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: selected ? accent : surface.withValues(alpha: 0),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: selected
                    ? AppColors.onAccentOf(context)
                    : AppColors.textSecondary(context),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: surface,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [segment('°C', false), segment('°F', true)],
      ),
    );
  }
}

/// The "How often" dropdown under Chaos Mode. Shown even with the global
/// switch off, because a single chat can still turn Chaos on in its sidebar.
class ChaosFrequencyPicker extends StatelessWidget {
  const ChaosFrequencyPicker({super.key, required this.storage});

  final StorageService storage;

  static String _describe(ChaosFrequency f) => switch (f) {
    ChaosFrequency.rare => 'Rare — about one event every twelve messages',
    ChaosFrequency.normal => 'Normal — about one every six or seven',
    ChaosFrequency.wild => 'Wild — about one every three',
  };

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'How often',
          style: TextStyle(
            color: AppColors.textSecondary(context),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        DropdownButton<ChaosFrequency>(
          isExpanded: true,
          value: storage.realismSettings.chaosFrequency,
          dropdownColor: AppColors.cardOf(context),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: AppColors.textPrimary(context),
            fontSize: 12,
          ),
          items: [
            for (final f in ChaosFrequency.values)
              DropdownMenuItem(
                value: f,
                child: Text(_describe(f), overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (v) {
            if (v != null) {
              storage.realismSettings.setChaosFrequency(v);
            }
          },
        ),
      ],
    );
  }
}

/// The "away for at least" dropdown that rides the absence-acknowledgement
/// row. Values are clamped to a known item so a hand-edited preference cannot
/// assert the dropdown (carried over verbatim from the old General tab).
class AwayThreshold extends StatelessWidget {
  const AwayThreshold({super.key, required this.storage});

  final StorageService storage;

  @override
  Widget build(BuildContext context) {
    const known = [12, 24, 72, 168];
    return Row(
      children: [
        Text(
          'Away for at least',
          style: TextStyle(
            color: AppColors.textSecondary(context),
            fontSize: 12,
          ),
        ),
        const Spacer(),
        DropdownButton<int>(
          value: known.contains(storage.realismSettings.absenceThresholdHours)
              ? storage.realismSettings.absenceThresholdHours
              : 24,
          dropdownColor: AppColors.cardOf(context),
          style: TextStyle(color: AppColors.textPrimary(context), fontSize: 12),
          items: const [
            DropdownMenuItem(value: 12, child: Text('12 hours')),
            DropdownMenuItem(value: 24, child: Text('a day')),
            DropdownMenuItem(value: 72, child: Text('3 days')),
            DropdownMenuItem(value: 168, child: Text('a week')),
          ],
          onChanged: (v) {
            if (v != null) storage.realismSettings.setAbsenceThresholdHours(v);
          },
        ),
      ],
    );
  }
}

/// Tavily API key under the Porch Life web-search row. Always
/// visible so a key can be pasted before the toggle is useful.
class WebSearchKeyField extends StatefulWidget {
  final StorageService storage;
  const WebSearchKeyField({super.key, required this.storage});

  @override
  State<WebSearchKeyField> createState() => _WebSearchKeyFieldState();
}

class _WebSearchKeyFieldState extends State<WebSearchKeyField> {
  final TextEditingController _controller = TextEditingController();
  bool _saving = false;
  String? _message;
  bool _saveFailed = false;

  Future<void> _save({bool clear = false}) async {
    final value = clear ? '' : _controller.text.trim();
    if (_saving || (!clear && value.isEmpty)) return;
    setState(() {
      _saving = true;
      _message = null;
    });
    try {
      await widget.storage.webSearchSettings.setSearchApiKey(value);
      if (!mounted) return;
      _controller.clear();
      setState(() {
        _saveFailed = false;
        _message = clear
            ? 'Key removed — searches use Wikipedia.'
            : 'Tavily key saved securely.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saveFailed = true;
        _message = 'Could not save the key securely.';
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasKey = widget.storage.webSearchSettings.hasApiKey;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _controller,
          obscureText: true,
          enabled: !_saving,
          style: TextStyle(color: AppColors.textPrimary(context), fontSize: 13),
          decoration: InputDecoration(
            isDense: true,
            hintText: hasKey ? 'Tavily key saved securely' : 'Tavily API key',
            hintStyle: TextStyle(color: AppColors.textTertiary(context)),
          ),
          onSubmitted: (_) => _save(),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.porchAmberOf(context),
                foregroundColor: AppColors.onAccentOf(context),
              ),
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'Saving…' : 'Save key'),
            ),
            if (hasKey)
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.porchAmberOf(context),
                ),
                onPressed: _saving ? null : () => _save(clear: true),
                child: const Text('Remove key'),
              ),
          ],
        ),
        if (_message != null) ...[
          const SizedBox(height: 6),
          Text(
            _message!,
            style: TextStyle(
              color: _saveFailed
                  ? AppColors.negativeAccentOf(context)
                  : AppColors.textSecondary(context),
              fontSize: 11,
            ),
          ),
        ],
      ],
    );
  }
}
