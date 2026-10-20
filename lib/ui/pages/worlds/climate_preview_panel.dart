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
// The editor's right-hand preview, styled 1:1 against the approved mockup:
// stacked season share bars with amber temperatures, a legend of (skinned)
// condition names, a bordered sample-week tile strip whose dangerous days
// glow red, tinted notice rows, and the code-owned "how a character will
// feel it" quote.

import 'package:flutter/material.dart';

import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/ui/pages/worlds/climate_editor_widgets.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';

/// Semantic weather-legend hues from the mockup — one recognizable color
/// per condition so the bars read as a legend, not chrome.
const Map<String, Color> kConditionLegendColors = {
  'clear': Color(0xFFD9A94E), // theme-keep: mockup weather legend
  'cloudy': Color(0xFF8D8496), // theme-keep: mockup weather legend
  'overcast': Color(0xFF6B6577), // theme-keep: mockup weather legend
  'fog': Color(0xFF9FB0BC), // theme-keep: mockup weather legend
  'rain': Color(0xFF5E7E99), // theme-keep: mockup weather legend
  'storm': Color(0xFF7A3F33), // theme-keep: mockup weather legend
  'snow': Color(0xFF9FB6C4), // theme-keep: mockup weather legend
};

class ClimatePreviewPanel extends StatelessWidget {
  const ClimatePreviewPanel({
    super.key,
    required this.preview,
    required this.biome,
    required this.fahrenheit,
  });

  final BiomePreview preview;
  final Biome biome;
  final bool fahrenheit;

  bool _dayIsDangerous(WeatherCondition c) {
    final skin = skinFor(biome, c);
    return skin != null &&
        (skin.stance == WeatherStance.dangerous ||
            skin.stance == WeatherStance.deadly);
  }

  @override
  Widget build(BuildContext context) {
    final extremeBands = [
      for (final b in TempBand.values)
        if (b.isExtreme &&
            preview.seasons.any((s) => (s.bandShare[b.name] ?? 0) > 0))
          b,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClimateSectionHeader(
          'Preview',
          hint: '${40 * 50} simulated days per season',
        ),
        for (final s in preview.seasons) _seasonRow(context, s),
        const SizedBox(height: 4),
        _legend(context),
        const SizedBox(height: 14),
        ClimateSectionHeader('A sample week', hint: 'winter · midday'),
        Row(
          children: [
            for (final (i, d) in preview.sampleWeek.indexed) ...[
              if (i > 0) const SizedBox(width: 6),
              Expanded(child: _dayTile(context, d)),
            ],
          ],
        ),
        if (preview.errors.isNotEmpty || preview.warnings.isNotEmpty) ...[
          const SizedBox(height: 14),
          ClimateSectionHeader('What the preview noticed'),
          for (final e in preview.errors) _notice(context, e, isError: true),
          for (final w in preview.warnings) _notice(context, w, isError: false),
        ],
        if (extremeBands.isNotEmpty) ...[
          const SizedBox(height: 14),
          ClimateSectionHeader('How a character will feel it'),
          for (final b in extremeBands)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                '“Outside it is ${WeatherSegments.dressCue(b)}.”',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.45,
                  fontStyle: FontStyle.italic,
                  color: AppColors.textSecondary(context),
                ),
              ),
            ),
          Text(
            '— code-owned survival prose, written by the app, not the author',
            style: TextStyle(
              fontSize: 10.5,
              color: AppColors.textTertiary(context),
            ),
          ),
        ],
      ],
    );
  }

  Widget _seasonRow(BuildContext context, SeasonDistribution s) {
    final entries = s.conditionShare.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 58,
            child: Text(
              seasonDisplayName(s.season, biome.seasonLabels),
              style: TextStyle(
                fontSize: 12.5,
                color: AppColors.textSecondary(context),
              ),
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                height: 16,
                child: Row(
                  children: [
                    for (final e in entries)
                      Expanded(
                        flex: (e.value * 1000).round().clamp(1, 1000),
                        child: ColoredBox(
                          color:
                              kConditionLegendColors[e.key] ??
                              AppColors.surfaceContainerOf(context),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 56,
            child: Text(
              '~${WeatherSegments.formatTemp(s.typicalTempC, fahrenheit: fahrenheit)}',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 11.5,
                color: AppColors.porchAmberOf(context),
                fontFamily: kMonoFallback.first,
                fontFamilyFallback: kMonoFallback,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dayTile(BuildContext context, SegmentWeather d) {
    final dangerous = _dayIsDangerous(d.condition);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerOf(context),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: dangerous
              ? kClimateDanger.withValues(alpha: 0.6)
              : AppColors.borderOf(context),
        ),
      ),
      child: Column(
        children: [
          Text(
            skinnedEmoji(biome, d.condition),
            style: const TextStyle(fontSize: 16),
          ),
          const SizedBox(height: 3),
          Text(
            WeatherSegments.formatTemp(d.tempC, fahrenheit: fahrenheit),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 10,
              color: AppColors.textSecondary(context),
              fontFamily: kMonoFallback.first,
              fontFamilyFallback: kMonoFallback,
            ),
          ),
        ],
      ),
    );
  }

  Widget _legend(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 4,
      children: [
        for (final e in kConditionLegendColors.entries)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 9,
                height: 9,
                margin: const EdgeInsets.only(right: 4),
                decoration: BoxDecoration(
                  color: e.value,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Text(
                skinnedConditionLabel(
                  biome,
                  WeatherCondition.values[kWeatherConditions.indexOf(e.key)],
                ),
                style: TextStyle(
                  fontSize: 10.5,
                  color: AppColors.textTertiary(context),
                ),
              ),
            ],
          ),
      ],
    );
  }

  /// Mockup notice rows: soft tinted background, no border, 8px radius —
  /// red tint for blockers, amber tint for advisories.
  Widget _notice(BuildContext context, String text, {required bool isError}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 7),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: isError
            ? kClimateDanger.withValues(alpha: 0.12)
            : kClimateWarn.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(isError ? '⛔ ' : '⚠️ ', style: const TextStyle(fontSize: 12)),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 11.5,
                height: 1.45,
                color: isError
                    ? StatusColors.noticeDangerOf(context)
                    : StatusColors.noticeWarnOf(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
