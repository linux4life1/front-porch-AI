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

part of 'realism_form_section.dart';

/// Engine master switch plus the fields that hide when it is off.
extension RealismFormEngine on RealismFormSection {
  List<Widget> _engineMasterToggle(BuildContext context) {
    return [
      // ── Master Toggle (can be hidden in group creator where the group-level toggle controls it) ──
      if (showMasterEnabledToggle)
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.cardOf(context),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: enabled
                  ? AppColors.formMasterAccent.withValues(alpha: 0.4)
                  : AppColors.borderOf(context),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: enabled
                      ? AppColors.formMasterAccent.withValues(alpha: 0.2)
                      : AppColors.surfaceContainerOf(
                          context,
                        ).withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.psychology,
                  color: enabled
                      ? AppColors.formMasterAccent
                      : AppColors.iconSecondary(context),
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Enable Realism Engine',
                      style: TextStyle(
                        color: AppColors.textPrimary(context),
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      enabled
                          ? 'Character will start with pre-configured state'
                          : 'Wardrobe, likes, time and Chaos still apply. '
                                'Bond, mood and Needs stay off.',
                      style: TextStyle(
                        color: enabled
                            ? AppColors.formMasterAccent
                            : AppColors.textTertiary(context),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: enabled,
                onChanged: onEnabledChanged,
                activeTrackColor: AppColors.formMasterAccent.withValues(
                  alpha: 0.5,
                ),
                activeThumbColor: AppColors.formMasterAccent,
              ),
            ],
          ),
        ),
    ];
  }

  List<Widget> _engineWhenOn(BuildContext context, TextStyle labelStyle) {
    return [
      if (enabled) ...[
        // Needs Simulation (rendered separately when provided by caller).
        // ignore: use_null_aware_elements — '?' doesn't work in children lists
        if (needsFormSection != null) needsFormSection!,

        // Relationship Section — one [RealismFormSection.sectionHeaderGap] above the header.
        Column(
          key: RealismFormSection.relationshipHeaderBlockKey,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: RealismFormSection.sectionHeaderGap),
            _sectionHeader(
              Icons.favorite,
              'Relationship',
              AppColors.relationshipAccent,
            ),
            const SizedBox(height: 12),
            Container(
              key: const Key('relationship-card'),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.cardOf(context),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.borderOf(context)),
              ),
              child: Column(
                children: [
                  // Short-Term Bond
                  _sliderRow(
                    label: 'Short-Term Bond',
                    value: shortTermBond,
                    min: -300,
                    max: 300,
                    tierName: _shortTermTierName(shortTermBond),
                    color: _bondColor(shortTermBond),
                    onChanged: (v) => onShortTermBondChanged(v.round()),
                    context: context,
                  ),
                  const SizedBox(height: 16),
                  // Long-Term Bond
                  _sliderRow(
                    label: 'Long-Term Bond',
                    value: longTermBond,
                    min: -300,
                    max: 300,
                    tierName: _longTermTierName(longTermBond),
                    color: _bondColor(longTermBond),
                    onChanged: (v) => onLongTermBondChanged(v.round()),
                    context: context,
                  ),
                  const SizedBox(height: 16),
                  // Trust Level
                  _sliderRow(
                    label: 'Trust Level',
                    value: trustLevel,
                    min: -100,
                    max: 100,
                    tierName: _trustLevelName(trustLevel),
                    color: _trustColor(trustLevel),
                    onChanged: (v) => onTrustLevelChanged(v.round()),
                    context: context,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: RealismFormSection.sectionHeaderGap),

        // Emotion Section
        _sectionHeader(Icons.mood, 'Starting Emotion', AppColors.emotionAccent),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.cardOf(context),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.borderOf(context)),
          ),
          child: Row(
            children: [
              // Emotion text field
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Emotion', style: labelStyle),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.surfaceContainerOf(context),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.borderOf(context)),
                      ),
                      // See the Day Number field: the controller must be
                      // owned, or mid-word edits jump to the end of the text.
                      child: SyncedTextField(
                        value: emotion,
                        style: TextStyle(
                          color: AppColors.textPrimary(context),
                          fontSize: 14,
                        ),
                        onChanged: onEmotionChanged,
                        decoration: InputDecoration(
                          hintText: 'e.g. curious, guarded, amused',
                          hintStyle: TextStyle(
                            color: AppColors.textTertiary(
                              context,
                            ).withValues(alpha: 0.6),
                            fontSize: 13,
                          ),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              // Intensity selector
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Intensity', style: labelStyle),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceContainerOf(context),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.borderOf(context)),
                      ),
                      child: DropdownButton<String>(
                        value: emotionIntensity,
                        isExpanded: true,
                        dropdownColor: AppColors.surfaceContainerOf(context),
                        underline: const SizedBox(),
                        style: TextStyle(
                          color: AppColors.textPrimary(context),
                          fontSize: 14,
                        ),
                        items: RealismFormSection._intensityOptions
                            .map(
                              (i) => DropdownMenuItem(
                                value: i,
                                child: Text(
                                  i[0].toUpperCase() + i.substring(1),
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (v) {
                          if (v != null) onEmotionIntensityChanged(v);
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Optional Toggles
        _sectionHeader(
          Icons.tune,
          'Optional Features',
          AppColors.optionalAccent,
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.cardOf(context),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.borderOf(context)),
          ),
          child: Column(
            children: [
              if (showNsfwCooldownToggle) ...[
                RealismFormSection.buildToggleRow(
                  icon: Icons.thermostat,
                  label: 'Afterglow (intimacy pacing)',
                  subtitle: 'Realistic arousal/refractory mechanics',
                  value: nsfwCooldownEnabled,
                  onChanged: onNsfwCooldownChanged,
                  context: context,
                ),
                if (showChaosToggle)
                  Divider(
                    color: AppColors.borderOf(context).withValues(alpha: 0.4),
                    height: 24,
                  ),
              ],
              if (showChaosToggle) ...[
                RealismFormSection.buildToggleRow(
                  icon: Icons.casino,
                  label: 'Chaos Mode (Chance Time)',
                  subtitle: 'Random narrative events during roleplay',
                  value: chaosModeEnabled,
                  onChanged: onChaosModeChanged,
                  context: context,
                ),
              ],

              // Realism Verification toggle (last optional; independent of needs).
              // Uses same _toggleRow + card styling. Sliders for passes/strictness are in Details dialog per spec.
              if (showVerificationToggle) ...[
                if (showChaosToggle || showNsfwCooldownToggle)
                  Divider(
                    color: AppColors.borderOf(context).withValues(alpha: 0.4),
                    height: 24,
                  ),
                RealismFormSection.buildToggleRow(
                  icon: Icons.verified_user,
                  label: 'Realism Verification (Director/Verifier)',
                  subtitle:
                      'Optional director thread validates realism deltas + needs JSON; supplies corrections + reason or re-feeds for reprocessing (extra eval cost; strong models recommended)',
                  value: realismVerificationEnabled,
                  onChanged: onRealismVerificationChanged,
                  context: context,
                ),
                // Compact sliders for the 2 tunables (shown in forms including group per-member when toggle visible).
                // 1-5 range; onChanged provided by caller (pages, group seed); defaults safe if not.
                const SizedBox(height: 8),
                Text(
                  'Max reprocess passes: $realismVerificationMaxReprocesses',
                  style: TextStyle(
                    color: AppColors.textSecondary(context),
                    fontSize: 11,
                  ),
                ),
                Slider(
                  value: realismVerificationMaxReprocesses.toDouble(),
                  min: 1,
                  max: 5,
                  divisions: 4,
                  label: '$realismVerificationMaxReprocesses',
                  onChanged: (d) => onRealismVerificationMaxReprocessesChanged
                      ?.call(d.round()),
                ),
                const SizedBox(height: 4),
                Text(
                  'Strictness (1=lenient … 5=strict): $realismVerificationStrictness',
                  style: TextStyle(
                    color: AppColors.textSecondary(context),
                    fontSize: 11,
                  ),
                ),
                Slider(
                  value: realismVerificationStrictness.toDouble(),
                  min: 1,
                  max: 5,
                  divisions: 4,
                  label: '$realismVerificationStrictness',
                  onChanged: (d) =>
                      onRealismVerificationStrictnessChanged?.call(d.round()),
                ),
              ],
            ],
          ),
        ),
      ],
    ];
  }
}
