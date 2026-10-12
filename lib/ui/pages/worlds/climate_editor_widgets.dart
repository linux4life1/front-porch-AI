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
// Shared pieces of the custom climate editor, styled 1:1 against the
// maintainer-approved mockup artifact (climate-editor-sketch): warm-porch
// card surfaces, mono numerals, amber accents, and the season-card grid.

import 'package:flutter/material.dart';

import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/ui/pages/worlds/climate_season_start.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Artifact palette notes: the amber/ink/surface/text roles map to
/// AppColors; the two semantic status hues below are the mockup's danger
/// and warn tones, used for stance pills, error rows, and notice tints.
const Color kClimateDanger = Color(0xFFE0644C); // theme-keep: mockup danger
const Color kClimateWarn = Color(0xFFE3B341); // theme-keep: mockup warn

/// Mono stack for every numeral (weights, anchors, temps, swing) — the
/// artifact sets numbers in SF Mono/Menlo.
const List<String> kMonoFallback = ['Menlo', 'Consolas', 'monospace'];

/// Thermal-ordered band choices for the per-season dropdowns.
const List<TempBand> kBandChoices = [
  TempBand.cryogenic,
  TempBand.cold,
  TempBand.cool,
  TempBand.mild,
  TempBand.warm,
  TempBand.hot,
  TempBand.furnace,
  TempBand.inferno,
];

String bandLabel(TempBand b) => switch (b) {
  TempBand.cryogenic => 'Cryogenic ❄',
  TempBand.cold => 'Cold',
  TempBand.cool => 'Cool',
  TempBand.mild => 'Mild',
  TempBand.warm => 'Warm',
  TempBand.hot => 'Hot',
  TempBand.furnace => 'Furnace 🔥',
  TempBand.inferno => 'Inferno 🔥',
};

/// Draft skin row state: stance stays null until the author picks one, which
/// is what lets Save enforce "a rename needs a danger level".
String stanceLabel(WeatherStance s) => switch (s) {
  WeatherStance.pleasant => 'Pleasant',
  WeatherStance.ordinary => 'Ordinary',
  WeatherStance.harsh => 'Harsh',
  WeatherStance.dangerous => 'Dangerous',
  WeatherStance.deadly => 'Deadly',
};

/// Stance → pill border/text color (mockup: ordinary grey, harsh warn,
/// dangerous/deadly danger).
Color stanceColor(BuildContext context, WeatherStance? s) => switch (s) {
  null => AppColors.textTertiary(context),
  WeatherStance.pleasant ||
  WeatherStance.ordinary => AppColors.textSecondary(context),
  WeatherStance.harsh => kClimateWarn,
  WeatherStance.dangerous || WeatherStance.deadly => kClimateDanger,
};

/// Section header in the artifact's register: small caps amber + hint.
class ClimateSectionHeader extends StatelessWidget {
  const ClimateSectionHeader(this.title, {super.key, this.hint});
  final String title;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title.toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w700,
            color: AppColors.porchAmberOf(context),
          ),
        ),
        if (hint != null) ...[
          const SizedBox(height: 3),
          Text(
            hint!,
            style: TextStyle(
              fontSize: 11,
              height: 1.4,
              color: AppColors.textTertiary(context),
            ),
          ),
        ],
        const SizedBox(height: 10),
      ],
    );
  }
}

/// One season CARD from the artifact's 4-across grid: surface panel with
/// the season name, the band dropdown, and the anchor row (mono amber input
/// + "°C shown" caption) — or the dimmed "auto" input when classic.
class SeasonCard extends StatelessWidget {
  const SeasonCard({
    super.key,
    required this.season,
    required this.band,
    required this.anchorController,
    required this.needsAnchor,
    required this.unit,
    required this.onBand,
    required this.onAnchorChanged,
    required this.labelController,
    required this.onLabelChanged,
    required this.startMonth,
    required this.startDay,
    required this.onStart,
    this.clash = false,
    this.onRemove,
  });

  final String season;
  final TempBand band;
  final TextEditingController anchorController;
  final bool needsAnchor;
  final String unit;
  final ValueChanged<TempBand> onBand;
  final VoidCallback onAnchorChanged;
  final TextEditingController labelController;
  final VoidCallback onLabelChanged;
  final int startMonth;
  final int startDay;
  final void Function(int month, int day) onStart;
  final bool clash;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final amber = AppColors.porchAmberOf(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerOf(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: clash ? kClimateDanger : AppColors.borderOf(context),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: labelController,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: kSeasons.contains(season)
                        ? season[0].toUpperCase() + season.substring(1)
                        : 'New season',
                    hintStyle: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textTertiary(context),
                    ),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                  ),
                  onChanged: (_) => onLabelChanged(),
                ),
              ),
              if (onRemove != null)
                IconButton(
                  tooltip: 'Remove season',
                  visualDensity: VisualDensity.compact,
                  iconSize: 16,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 24,
                    minHeight: 24,
                  ),
                  onPressed: onRemove,
                  icon: Icon(
                    Icons.close,
                    size: 16,
                    color: AppColors.textTertiary(context),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          SeasonStartRow(
            month: startMonth,
            day: startDay,
            onStart: onStart,
            clash: clash,
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: AppColors.resolve(context, Colors.black26, Colors.white54),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.borderOf(context)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<TempBand>(
                value: band,
                isExpanded: true,
                isDense: true,
                dropdownColor: AppColors.surfaceContainerOf(context),
                style: TextStyle(
                  fontSize: 12.5,
                  color: AppColors.textPrimary(context),
                ),
                items: [
                  for (final b in kBandChoices)
                    DropdownMenuItem(value: b, child: Text(bandLabel(b))),
                ],
                onChanged: (b) {
                  if (b != null) onBand(b);
                },
              ),
            ),
          ),
          const SizedBox(height: 8),
          // Mockup: `[64px mono input] °C shown`. The caption is Flexible so
          // the row can never overflow the card, and sized so the full
          // "°F shown" fits at the dialog's spec width.
          Row(
            children: [
              SizedBox(
                width: 56,
                child: needsAnchor
                    ? TextField(
                        controller: anchorController,
                        keyboardType: const TextInputType.numberWithOptions(
                          signed: true,
                        ),
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontSize: 13,
                          color: amber,
                          fontFamily: kMonoFallback.first,
                          fontFamilyFallback: kMonoFallback,
                        ),
                        decoration: InputDecoration(
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 6,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(7),
                            borderSide: BorderSide(color: amber),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(7),
                            borderSide: BorderSide(color: amber, width: 1.4),
                          ),
                        ),
                        onChanged: (_) => onAnchorChanged(),
                      )
                    : Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(7),
                          border: Border.all(
                            color: AppColors.borderOf(context),
                          ),
                        ),
                        child: Text(
                          'auto',
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.textTertiary(context),
                            fontFamily: kMonoFallback.first,
                            fontFamilyFallback: kMonoFallback,
                          ),
                        ),
                      ),
              ),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  needsAnchor ? '$unit shown' : unit,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.fade,
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textTertiary(context),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The 4-season × 7-condition weights grid, artifact-styled: mono numerals,
/// dimmed zeros, and an amber-edged cell on each season's dominant weight.
class WeightsGrid extends StatelessWidget {
  const WeightsGrid({
    super.key,
    required this.controllers,
    required this.seasons,
    this.labels = const {},
  });

  /// season → 7 controllers in [kWeatherConditions] order.
  final Map<String, List<TextEditingController>> controllers;
  final List<String> seasons;
  final Map<String, String> labels;

  @override
  Widget build(BuildContext context) {
    final tertiary = AppColors.textTertiary(context);
    final amberEdge = AppColors.porchAmberOf(context).withValues(alpha: 0.55);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Table(
        defaultColumnWidth: const FixedColumnWidth(62),
        columnWidths: const {0: FixedColumnWidth(66)},
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        children: [
          TableRow(
            children: [
              const SizedBox.shrink(),
              for (final c in kWeatherConditions)
                Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: Text(
                    c[0].toUpperCase() + c.substring(1),
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 10.5, color: tertiary),
                  ),
                ),
            ],
          ),
          for (final season in seasons)
            TableRow(
              children: [
                Text(
                  seasonDisplayName(season, labels),
                  style: TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textSecondary(context),
                  ),
                ),
                for (final ctl in controllers[season]!)
                  Padding(
                    padding: const EdgeInsets.all(2.5),
                    child: ValueListenableBuilder<TextEditingValue>(
                      valueListenable: ctl,
                      builder: (context, value, _) {
                        final n = int.tryParse(value.text.trim()) ?? 0;
                        final rowMax = controllers[season]!
                            .map((c) => int.tryParse(c.text.trim()) ?? 0)
                            .fold(0, (a, b) => a > b ? a : b);
                        final isMax = n > 0 && n == rowMax;
                        return TextField(
                          controller: ctl,
                          textAlign: TextAlign.center,
                          keyboardType: TextInputType.number,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: n == 0
                                ? tertiary
                                : AppColors.textPrimary(context),
                            fontFamily: kMonoFallback.first,
                            fontFamilyFallback: kMonoFallback,
                          ),
                          decoration: InputDecoration(
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 7,
                            ),
                            filled: true,
                            fillColor: AppColors.surfaceContainerOf(context),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(6),
                              borderSide: BorderSide(
                                color: isMax
                                    ? amberEdge
                                    : AppColors.borderOf(context),
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(6),
                              borderSide: BorderSide(
                                color: AppColors.porchAmberOf(context),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

/// The day–night swing slider with the artifact's amber fill, glowing knob,
/// and mono "N.N× Earth" readout.
class SwingSlider extends StatelessWidget {
  const SwingSlider({super.key, required this.value, required this.onChanged});

  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final amber = AppColors.porchAmberOf(context);
    return Row(
      children: [
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              activeTrackColor: amber,
              inactiveTrackColor: AppColors.surfaceContainerOf(context),
              thumbColor: amber,
              overlayColor: amber.withValues(alpha: 0.25),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            ),
            child: Slider(
              value: value.clamp(0.2, 4.0),
              min: 0.2,
              max: 4.0,
              divisions: 19,
              onChanged: onChanged,
            ),
          ),
        ),
        SizedBox(
          width: 86,
          child: Text(
            '${value.toStringAsFixed(1)}× Earth',
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 13,
              color: amber,
              fontFamily: kMonoFallback.first,
              fontFamilyFallback: kMonoFallback,
            ),
          ),
        ),
      ],
    );
  }
}
