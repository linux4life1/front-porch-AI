// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

part of 'greeting_seed_form.dart';

extension _GreetingSeedSections on _GreetingSeedFormState {
  Widget _header(IconData icon, String text, Color color) => Row(
    children: [
      Icon(icon, color: color, size: 18),
      const SizedBox(width: 8),
      Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
    ],
  );

  Widget _card(Widget child) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppColors.cardOf(context),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.borderOf(context)),
    ),
    child: child,
  );

  TextStyle get _labelStyle => TextStyle(
    color: AppColors.textSecondary(context),
    fontSize: 12,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.5,
  );

  Widget _timeSection(GreetingRealismSeed s) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(
          Icons.schedule,
          'Time & Day',
          AppColors.timeDayAccentOf(context),
        ),
        const SizedBox(height: 12),
        _card(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 2,
                    child: _dropdown(
                      label: 'Time of Day',
                      value: s.timeOfDay,
                      items: _GreetingSeedFormState._times,
                      hint: 'inherit (morning)',
                      onChanged: (v) =>
                          widget.onChanged(s.copyWith(timeOfDay: v)),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _labeledField(
                      label: 'Day Number',
                      child: _boxedField(
                        SyncedTextField(
                          value: s.dayCount?.toString() ?? '',
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          onChanged: (v) {
                            final n = int.tryParse(v.trim());
                            if (v.trim().isEmpty || n == 0) {
                              widget.onChanged(s.copyWith(dayCount: null));
                            } else if (n != null && n >= 1) {
                              widget.onChanged(s.copyWith(dayCount: n));
                            }
                          },
                          style: TextStyle(
                            color: AppColors.textPrimary(context),
                            fontSize: 14,
                          ),
                          decoration: _deco('inherit (day 1)'),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              StoryBeginsRow(
                storyStartDate: s.storyStartDate,
                onStoryStartDateChanged: (v) =>
                    widget.onChanged(s.copyWith(storyStartDate: v)),
                storyStartTime: s.storyStartTime,
                onStoryStartTimeChanged: (v) =>
                    widget.onChanged(s.copyWith(storyStartTime: v)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _relationshipSection(GreetingRealismSeed s) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(
          Icons.favorite,
          'Relationship',
          AppColors.relationshipAccentOf(context),
        ),
        const SizedBox(height: 12),
        _card(
          Column(
            children: [
              SliderWithInput(
                label: 'Short-term bond',
                value: (s.shortTermBond ?? 0).toDouble(),
                unset: s.shortTermBond == null,
                min: -300,
                max: 300,
                isInteger: true,
                divisions: 600,
                context: context,
                onChanged: (v) =>
                    widget.onChanged(s.copyWith(shortTermBond: v.round())),
                onCleared: () =>
                    widget.onChanged(s.copyWith(shortTermBond: null)),
              ),
              SliderWithInput(
                label: 'Long-term bond',
                value: (s.longTermBond ?? 0).toDouble(),
                unset: s.longTermBond == null,
                min: -300,
                max: 300,
                isInteger: true,
                divisions: 600,
                context: context,
                onChanged: (v) =>
                    widget.onChanged(s.copyWith(longTermBond: v.round())),
                onCleared: () =>
                    widget.onChanged(s.copyWith(longTermBond: null)),
              ),
              SliderWithInput(
                label: 'Trust',
                value: (s.trustLevel ?? 0).toDouble(),
                unset: s.trustLevel == null,
                min: -100,
                max: 100,
                isInteger: true,
                divisions: 200,
                context: context,
                onChanged: (v) =>
                    widget.onChanged(s.copyWith(trustLevel: v.round())),
                onCleared: () => widget.onChanged(s.copyWith(trustLevel: null)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _emotionSection(GreetingRealismSeed s) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(
          Icons.mood,
          'Starting Emotion',
          AppColors.emotionAccentOf(context),
        ),
        const SizedBox(height: 12),
        _card(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 2,
                    child: _labeledField(
                      label: 'Emotion',
                      child: _boxedField(
                        SyncedTextField(
                          value: s.characterEmotion ?? '',
                          onChanged: (v) => widget.onChanged(
                            s.copyWith(
                              characterEmotion: v.trim().isEmpty
                                  ? null
                                  : v.trim(),
                            ),
                          ),
                          style: TextStyle(
                            color: AppColors.textPrimary(context),
                            fontSize: 14,
                          ),
                          decoration: _deco('e.g. furious, warm, guarded'),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _dropdown(
                      label: 'Intensity',
                      value: s.emotionIntensity,
                      items: _GreetingSeedFormState._intensities,
                      hint: 'inherit (mild)',
                      onChanged: (v) =>
                          widget.onChanged(s.copyWith(emotionIntensity: v)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _labeledField(
                label: 'Starting task',
                child: _boxedField(
                  SyncedTextField(
                    value: s.currentTask ?? '',
                    onChanged: (v) => widget.onChanged(
                      s.copyWith(
                        currentTask: v.trim().isEmpty ? null : v.trim(),
                      ),
                    ),
                    style: TextStyle(
                      color: AppColors.textPrimary(context),
                      fontSize: 14,
                    ),
                    decoration: _deco('Optional in-voice objective'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _needsSection(GreetingRealismSeed s) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(
          Icons.battery_std,
          'Needs Simulation',
          AppColors.verifiedAccentOf(context),
        ),
        const SizedBox(height: 12),
        _card(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Baselines (0–100, higher = more sated). Blank inherits the '
                'card. Pace stays on the card.',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.35,
                  color: AppColors.textSecondary(context),
                ),
              ),
              const SizedBox(height: 8),
              for (final need in _GreetingSeedFormState._needs)
                SliderWithInput(
                  label: need.$1,
                  value: (need.$2(s) ?? 80).toDouble(),
                  unset: need.$2(s) == null,
                  min: 0,
                  max: 100,
                  isInteger: true,
                  divisions: 100,
                  context: context,
                  onChanged: (v) => widget.onChanged(need.$3(s, v.round())),
                  onCleared: () => widget.onChanged(need.$4(s)),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _dropdown({
    required String label,
    required String? value,
    required List<String> items,
    required String hint,
    required ValueChanged<String?> onChanged,
  }) {
    final selected = value != null && items.contains(value) ? value : null;
    final inheritStyle = TextStyle(
      color: AppColors.textTertiary(context).withValues(alpha: 0.6),
      fontSize: 13,
    );
    return _labeledField(
      label: label,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerOf(context),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.borderOf(context)),
        ),
        child: DropdownButtonFormField<String>(
          key: ValueKey('$label-${selected ?? 'inherit'}'),
          initialValue: selected,
          hint: Text(hint, style: inheritStyle),
          items: [
            DropdownMenuItem<String>(
              value: null,
              child: Text(hint, style: inheritStyle),
            ),
            for (final i in items)
              DropdownMenuItem(value: i, child: Text(i.replaceAll('_', ' '))),
          ],
          onChanged: onChanged,
          decoration: const InputDecoration(
            border: InputBorder.none,
            contentPadding: EdgeInsets.symmetric(vertical: 10),
          ),
          dropdownColor: AppColors.surfaceContainerOf(context),
          style: TextStyle(color: AppColors.textPrimary(context), fontSize: 14),
        ),
      ),
    );
  }

  Widget _labeledField({required String label, required Widget child}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: _labelStyle),
        const SizedBox(height: 8),
        child,
      ],
    );
  }

  Widget _boxedField(Widget child) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerOf(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: child,
    );
  }

  InputDecoration _deco(String? hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(
        color: AppColors.textTertiary(context).withValues(alpha: 0.6),
        fontSize: 13,
      ),
      border: InputBorder.none,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    );
  }
}
