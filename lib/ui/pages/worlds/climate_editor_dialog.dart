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

import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/ui/pages/worlds/climate_editor_right.dart';
import 'package:front_porch_ai/ui/pages/worlds/climate_season_strip.dart';
import 'package:front_porch_ai/ui/pages/worlds/worlds.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

/// Custom climate editor. Desktop authoring; biome JSON is consumed everywhere.
/// Anchors are typed in the user's °C/°F unit and stored as °C.
Future<String?> showClimateEditorDialog(
  BuildContext context, {
  required String worldName,
  String? existingBiomeJson,
  required bool fahrenheit,
}) {
  return showDialog<String?>(
    context: context,
    builder: (_) => _ClimateEditorDialog(
      worldName: worldName,
      existingBiomeJson: existingBiomeJson,
      fahrenheit: fahrenheit,
    ),
  );
}

class _ClimateEditorDialog extends StatefulWidget {
  const _ClimateEditorDialog({
    required this.worldName,
    required this.existingBiomeJson,
    required this.fahrenheit,
  });

  final String worldName;
  final String? existingBiomeJson;
  final bool fahrenheit;

  @override
  State<_ClimateEditorDialog> createState() => _ClimateEditorDialogState();
}

class _ClimateEditorDialogState extends State<_ClimateEditorDialog> {
  late String _templateId;
  final Map<String, TempBand> _seasonBand = {};
  final Map<String, TextEditingController> _anchorCtls = {
    for (final s in kSeasons) s: TextEditingController(),
  };
  final Map<String, TextEditingController> _labelCtls = {
    for (final s in kSeasons) s: TextEditingController(),
  };
  final Map<String, int> _startMonth = {
    for (final s in kSeasons) s: monthDayFromDoy(kEarthSeasonStarts[s]!).$1,
  };
  final Map<String, int> _startDay = {
    for (final s in kSeasons) s: monthDayFromDoy(kEarthSeasonStarts[s]!).$2,
  };
  final Map<String, List<TextEditingController>> _weightCtls = {
    for (final s in kSeasons)
      s: [
        for (var i = 0; i < kWeatherConditions.length; i++)
          TextEditingController(),
      ],
  };
  final Map<String, SkinDraft> _skins = {
    for (final c in kWeatherConditions) c: SkinDraft(),
  };
  final Map<String, TextEditingController> _skinLabelCtls = {
    for (final c in kWeatherConditions) c: TextEditingController(),
  };
  final Map<String, TextEditingController> _skinFlavourCtls = {
    for (final c in kWeatherConditions) c: TextEditingController(),
  };
  double _diurnal = 1.0;
  BiomePreview? _preview;
  List<String> _ids = List<String>.from(kSeasons);

  int _toDisplay(int c) => widget.fahrenheit ? WeatherSegments.tempF(c) : c;
  int _fromDisplay(int v) => widget.fahrenheit ? ((v - 32) * 5 / 9).round() : v;
  String get _unit => widget.fahrenheit ? '°F' : '°C';

  @override
  void initState() {
    super.initState();
    final existing = Biome.tryParse(widget.existingBiomeJson);
    _templateId = existing != null ? 'custom' : Biome.desert.id;
    _seedFrom(existing ?? Biome.desert);
    // The mockup opens with the preview already computed.
    _preview = previewBiome(_buildDraft());
    _startState = _editState;
  }

  String get _draftJson => jsonEncode(_buildDraft().toJson());
  String get _editState => climateEditState(_draftJson, _skins, [
    _anchorCtls,
    _labelCtls,
  ], _weightCtls);
  late final String _startState;

  void _ensureSeason(String id) {
    if (_labelCtls.containsKey(id)) return;
    _labelCtls[id] = TextEditingController();
    _anchorCtls[id] = TextEditingController();
    _seasonBand[id] = TempBand.mild;
    _startMonth[id] = 6;
    _startDay[id] = 1;
    _weightCtls[id] = [
      for (var i = 0; i < kWeatherConditions.length; i++)
        TextEditingController(),
    ];
  }

  void _dropSeason(String id) {
    _anchorCtls.remove(id)?.dispose();
    _labelCtls.remove(id)?.dispose();
    _seasonBand.remove(id);
    _startMonth.remove(id);
    _startDay.remove(id);
    final w = _weightCtls.remove(id);
    if (w != null) {
      for (final c in w) {
        c.dispose();
      }
    }
  }

  void _seedFrom(Biome b) {
    final next = List<String>.from(b.seasonIds);
    for (final id in List<String>.from(_ids)) {
      if (!next.contains(id)) _dropSeason(id);
    }
    _ids = next;
    for (final season in _ids) {
      _ensureSeason(season);
      final idx = (b.baseTemp[season] ?? 2).clamp(
        0,
        TempBand.values.length - 1,
      );
      _seasonBand[season] = TempBand.values[idx];
      final anchor = b.displayAnchorsC[season];
      _anchorCtls[season]!.text = anchor != null ? '${_toDisplay(anchor)}' : '';
      _labelCtls[season]!.text = b.seasonLabels[season] ?? '';
      final md = monthDayFromDoy(
        b.seasonStarts[season] ?? kEarthSeasonStarts[season] ?? 1,
      );
      _startMonth[season] = md.$1;
      _startDay[season] = md.$2;
      final weights =
          b.weights[season] ?? List<int>.filled(kWeatherConditions.length, 0);
      for (var i = 0; i < kWeatherConditions.length; i++) {
        _weightCtls[season]![i].text = '${i < weights.length ? weights[i] : 0}';
      }
    }
    _diurnal = b.diurnalAmplitude;
    for (final c in kWeatherConditions) {
      final skin = b.conditionSkin[c];
      final draft = _skins[c]!;
      draft.label = skin?.label ?? '';
      draft.emoji = skin?.emoji ?? '';
      draft.stance = skin?.stance;
      draft.flavour = skin?.flavour ?? '';
      _skinLabelCtls[c]!.text = draft.label;
      _skinFlavourCtls[c]!.text = draft.flavour;
    }
  }

  @override
  void dispose() {
    for (final c in [
      ..._anchorCtls.values,
      ..._labelCtls.values,
      for (final list in _weightCtls.values) ...list,
      ..._skinLabelCtls.values,
      ..._skinFlavourCtls.values,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  bool _needsAnchor(String season) {
    final range = _derivedRange();
    final rank = _seasonBand[season]!.rank;
    final lo = (rank - 1).clamp(range.$1, range.$2);
    final hi = (rank + 1).clamp(range.$1, range.$2);
    return lo < kClassicBandRange.$1 || hi > kClassicBandRange.$2;
  }

  (int, int) _derivedRange() {
    final ranks = [for (final s in _ids) _seasonBand[s]!.rank];
    final anyExtreme = ranks.any(
      (r) => r < kClassicBandRange.$1 || r > kClassicBandRange.$2,
    );
    if (!anyExtreme) return kClassicBandRange;
    final lo = ranks.reduce((a, b) => a < b ? a : b) - 1;
    final hi = ranks.reduce((a, b) => a > b ? a : b) + 1;
    return (
      lo.clamp(kFullBandRange.$1, kFullBandRange.$2),
      hi.clamp(kFullBandRange.$1, kFullBandRange.$2),
    );
  }

  Biome _buildDraft() {
    final range = _derivedRange();
    return Biome(
      id: 'custom',
      displayName: widget.worldName.trim().isEmpty
          ? 'Custom climate'
          : widget.worldName.trim(),
      description: 'Custom climate for ${widget.worldName}',
      weights: {
        for (final s in _ids)
          s: [
            for (final ctl in _weightCtls[s]!)
              (int.tryParse(ctl.text.trim()) ?? 0).clamp(0, 999),
          ],
      },
      baseTemp: {for (final s in _ids) s: _seasonBand[s]!.index},
      bandRange: range,
      displayAnchorsC: {
        for (final s in _ids)
          if (_needsAnchor(s) &&
              int.tryParse(_anchorCtls[s]!.text.trim()) != null)
            s: _fromDisplay(
              int.parse(_anchorCtls[s]!.text.trim()),
            ).clamp(-273, 2000),
      },
      diurnalAmplitude: _diurnal,
      seasonLabels: {
        for (final s in _ids)
          if (_labelCtls[s]!.text.trim().isNotEmpty)
            s: _labelCtls[s]!.text.trim(),
      },
      seasonStarts: () {
        final starts = {
          for (final s in _ids)
            s: doyFromMonthDay(_startMonth[s]!, _startDay[s]!),
        };
        return seasonStartsEqualEarth(starts) ? const <String, int>{} : starts;
      }(),
      conditionSkin: {
        for (final e in _skins.entries)
          if (e.value.active && e.value.stance != null)
            e.key: ConditionSkin(
              label: e.value.label.trim(),
              emoji: e.value.emoji.trim().isEmpty ? null : e.value.emoji.trim(),
              stance: e.value.stance!,
              flavour: e.value.flavour.trim().isEmpty
                  ? null
                  : e.value.flavour.trim(),
            ),
      },
    );
  }

  List<String> _blockingErrors() {
    final errors = _buildDraft().validate();
    for (final e in _skins.entries) {
      if (e.value.active && e.value.stance == null) {
        errors.add(
          '${e.key}: a renamed weather needs a danger level — otherwise '
          'characters would picnic in it.',
        );
      }
    }
    return [for (final e in errors) displayUnitError(e, widget.fahrenheit)];
  }

  void _refreshPreview() =>
      setState(() => _preview = previewBiome(_buildDraft()));

  void _addSeason() {
    if (_ids.length >= kMaxSeasons) return;
    setState(() {
      final id = allocSeasonId(_ids);
      _ensureSeason(id);
      final starts = {
        for (final s in _ids)
          s: doyFromMonthDay(_startMonth[s]!, _startDay[s]!),
      };
      final md = monthDayFromDoy(startInLongestGap(starts));
      _startMonth[id] = md.$1;
      _startDay[id] = md.$2;
      final src = _ids.contains('summer') ? 'summer' : _ids.first;
      _seasonBand[id] = _seasonBand[src] ?? TempBand.mild;
      for (var i = 0; i < kWeatherConditions.length; i++) {
        _weightCtls[id]![i].text = _weightCtls[src]![i].text;
      }
      _labelCtls[id]!.text = 'Season ${_ids.length + 1}';
      _ids.add(id);
      _preview = previewBiome(_buildDraft());
    });
  }

  void _removeSeason(String id) {
    if (_ids.length <= kMinSeasons) return;
    setState(() {
      _ids.remove(id);
      _dropSeason(id);
      _preview = previewBiome(_buildDraft());
    });
  }

  @override
  Widget build(BuildContext context) {
    final errors = _blockingErrors();
    return UnsavedChangesGuard(
      isDirty: () => _editState != _startState,
      child: Dialog(
        backgroundColor: AppColors.cardOf(context),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: AppColors.borderOf(context)),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1120, maxHeight: 760),
          child: Column(
            children: [
              // ── Header with the mockup's amber wash ──
              ClimateEditorHeader(
                worldName: widget.worldName,
                templateId: _templateId,
                onTemplate: (id) {
                  if (id == 'custom') return;
                  setState(() {
                    _templateId = id;
                    _seedFrom(Biome.builtInById(id)!);
                    _preview = previewBiome(_buildDraft());
                  });
                },
                onClose: () => Navigator.maybePop(context),
              ),
              Divider(height: 1, color: AppColors.borderOf(context)),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(flex: 5, child: _leftColumn(context)),
                    VerticalDivider(
                      width: 1,
                      color: AppColors.borderOf(context),
                    ),
                    // The mockup's darker inset preview column.
                    Expanded(
                      flex: 4,
                      child: ColoredBox(
                        color: InkColors.dim(0.14),
                        child: _rightColumn(context),
                      ),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: AppColors.borderOf(context)),
              // ── Footer pills ──
              ClimateEditorFooter(
                canSave: errors.isEmpty,
                onCancel: () => Navigator.maybePop(context),
                onSave: () => Navigator.pop(context, _draftJson),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _leftColumn(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      children: [
        ClimateSectionHeader(
          'Temperature by season',
          hint:
              '2–8 seasons. Same start twice cannot save. '
              'Extreme steps unlock the display $_unit. Storage stays °C.',
        ),
        ClimateSeasonStrip(
          ids: _ids,
          band: _seasonBand,
          anchorCtls: _anchorCtls,
          labelCtls: _labelCtls,
          startMonth: _startMonth,
          startDay: _startDay,
          unit: _unit,
          needsAnchor: _needsAnchor,
          clash: (s) => _blockingErrors().any((e) => e.contains(s)),
          onBand: (s, b) => setState(() => _seasonBand[s] = b),
          onAnchorChanged: () => setState(() {}),
          onLabelChanged: () => setState(() {}),
          onStart: (s, m, d) => setState(() {
            _startMonth[s] = m;
            _startDay[s] = d;
            _preview = previewBiome(_buildDraft());
          }),
          onRemove: _removeSeason,
          onAdd: _addSeason,
        ),
        const SizedBox(height: 20),
        ClimateSectionHeader(
          'Weather odds',
          hint: 'Per season — higher numbers are more common.',
        ),
        WeightsGrid(
          controllers: _weightCtls,
          seasons: _ids,
          labels: {
            for (final s in _ids)
              if (_labelCtls[s]!.text.trim().isNotEmpty)
                s: _labelCtls[s]!.text.trim(),
          },
        ),
        const SizedBox(height: 20),
        ClimateSectionHeader('Day–night swing'),
        SwingSlider(
          value: _diurnal,
          onChanged: (v) => setState(() => _diurnal = v),
        ),
        Text(
          'How hard the temperature drops after sundown. Deserts and thin '
          'atmospheres swing hard.',
          style: TextStyle(
            fontSize: 11,
            color: AppColors.textTertiary(context),
          ),
        ),
        const SizedBox(height: 20),
        ClimateSectionHeader(
          'Rename the weather',
          hint:
              'Every rename needs a danger level, so a lazy "acid rain" '
              'still behaves. Leave blank to keep the normal weather.',
        ),
        for (final c in kWeatherConditions)
          SkinEditRow(
            condition: c,
            draft: _skins[c]!,
            labelController: _skinLabelCtls[c]!,
            flavourController: _skinFlavourCtls[c]!,
            onLabel: (v) => setState(() => _skins[c]!.label = v),
            onEmoji: (v) => setState(() => _skins[c]!.emoji = v),
            onFlavour: (v) => setState(() => _skins[c]!.flavour = v),
            onStance: (st) => setState(() => _skins[c]!.stance = st),
          ),
        const SizedBox(height: 6),
        Text(
          'Standing facts about the place — air, gravity, what\'s '
          'underfoot — don\'t belong to the climate. They live in the '
          'world\'s Place traits, right below the climate picker.',
          style: TextStyle(
            fontSize: 11,
            height: 1.4,
            color: AppColors.textTertiary(context),
          ),
        ),
      ],
    );
  }

  Widget _rightColumn(BuildContext context) {
    return ClimateEditorRightColumn(
      preview: _preview,
      biome: _buildDraft(),
      fahrenheit: widget.fahrenheit,
      errors: _blockingErrors(),
      onRefresh: _refreshPreview,
    );
  }
}
