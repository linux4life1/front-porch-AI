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

/// Porch Life: time, Chaos when the engine is off, identity / wardrobe.
extension RealismFormPorch on RealismFormSection {
  List<Widget> _porchTime(BuildContext context, TextStyle labelStyle) {
    return [
      // Time / Chaos / identity chips are Porch Life — they run without
      // the engine. Do not hide them behind [enabled].
      const SizedBox(height: 20),

      if (showTimeAndDay) ...[
        // Time & Day Section
        _sectionHeader(Icons.schedule, 'Time & Day', AppColors.timeDayAccent),
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
              // Time of Day dropdown
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Time of Day', style: labelStyle),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceContainerOf(context),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.borderOf(context)),
                      ),
                      child: DropdownButton<String>(
                        value: timeOfDay,
                        isExpanded: true,
                        dropdownColor: AppColors.surfaceContainerOf(context),
                        underline: const SizedBox(),
                        style: TextStyle(
                          color: AppColors.textPrimary(context),
                          fontSize: 14,
                        ),
                        items: RealismFormSection._timeOptions
                            .map(
                              (t) => DropdownMenuItem(
                                value: t,
                                child: Text(_formatTimeLabel(t)),
                              ),
                            )
                            .toList(),
                        onChanged: (v) {
                          if (v != null) onTimeOfDayChanged(v);
                        },
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              // Day Number
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Day Number', style: labelStyle),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.surfaceContainerOf(context),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.borderOf(context)),
                      ),
                      // SyncedTextField, not a TextField with an inline
                      // controller: every caller rebuilds this section on
                      // each keystroke, and a controller built in build()
                      // loses the caret (and any IME composition) every
                      // frame.
                      child: SyncedTextField(
                        value: dayCount.toString(),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        style: TextStyle(
                          color: AppColors.textPrimary(context),
                          fontSize: 14,
                        ),
                        onChanged: (v) {
                          final n = int.tryParse(v);
                          if (n != null && n >= 1) onDayCountChanged(n);
                        },
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (onStoryStartDateChanged != null) ...[
          const SizedBox(height: 8),
          StoryBeginsRow(
            storyStartDate: storyStartDate,
            onStoryStartDateChanged: onStoryStartDateChanged!,
            storyStartTime: storyStartTime,
            onStoryStartTimeChanged: onStoryStartTimeChanged,
          ),
        ],
      ], // end showTimeAndDay
    ];
  }

  List<Widget> _porchAfterEngine(BuildContext context) {
    return [
      if (showChaosToggle && !enabled) ...[
        const SizedBox(height: 20),
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
          child: RealismFormSection.buildToggleRow(
            icon: Icons.casino,
            label: 'Chaos Mode (Chance Time)',
            subtitle: 'Random narrative events during roleplay',
            value: chaosModeEnabled,
            onChanged: onChaosModeChanged,
            context: context,
          ),
        ),
      ],

      // Identity / wardrobe — Porch Life, not the engine.
      IdentityChipLists(
        ambitions: ambitions,
        onAmbitionsChanged: onAmbitionsChanged,
        planLines: planLines,
        onPlanLinesChanged: onPlanLinesChanged,
        occupation: occupation,
        onOccupationChanged: onOccupationChanged,
        occupationBrief: occupationBrief,
        onOccupationBriefChanged: onOccupationBriefChanged,
        hours: hours,
        onHoursChanged: onHoursChanged,
        workDays: workDays,
        onWorkDaysChanged: onWorkDaysChanged,
        birthday: birthday,
        onBirthdayChanged: onBirthdayChanged,
        birthdayAgeAsOf: birthdayAgeAsOf,
        likes: likes,
        onLikesChanged: onLikesChanged,
        dislikes: dislikes,
        onDislikesChanged: onDislikesChanged,
        intimateInto: intimateInto,
        onIntimateIntoChanged: onIntimateIntoChanged,
        intimateNotInto: intimateNotInto,
        onIntimateNotIntoChanged: onIntimateNotIntoChanged,
        showIntimate: showIntimate,
        worn: worn,
        onWornChanged: onWornChanged,
        carrying: carrying,
        onCarryingChanged: onCarryingChanged,
      ),
    ];
  }
}
