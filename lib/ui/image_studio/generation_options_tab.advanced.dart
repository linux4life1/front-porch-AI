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

part of 'generation_options_tab.dart';

// Draw Things' sampler enum is wire-protocol (label -> gRPC int value); moved
// here verbatim from the shell since it's only read by _buildAdvancedFields
// below. Keep as ONE copy — duplicating it would fork the wire values.
const List<({String label, int value})> _drawThingsSamplers = [
  (label: 'DDIM Trailing', value: 16),
  (label: 'UniPC Trailing', value: 17),
  (label: 'Euler a Trailing', value: 10),
  (label: 'DPM++ 2M Trailing', value: 15),
  (label: 'DPM++ SDE Trailing', value: 11),
  (label: 'UniPC AYS', value: 18),
  (label: 'Euler a AYS', value: 13),
  (label: 'DPM++ 2M AYS', value: 12),
  (label: 'DPM++ SDE AYS', value: 14),
  (label: 'DPM++ 2M Karras', value: 0),
  (label: 'DPM++ SDE Karras', value: 4),
  (label: 'Euler a', value: 1),
  (label: 'UniPC', value: 5),
  (label: 'DDIM', value: 2),
  (label: 'PLMS', value: 3),
  (label: 'LCM', value: 6),
  (label: 'TCD', value: 9),
  (label: 'Euler a Substep', value: 7),
  (label: 'DPM++ SDE Substep', value: 8),
];

/// The Advanced knobs (Steps/CFG/Sampler/Scheduler/Seed + DT Advanced cluster)
/// for [_GenerationOptionsTabState], split out of the shell to keep every file
/// under the 500-LOC cap (mirrors the settings_page.dart `part of` pattern).
/// These methods keep direct access to the tab's private state, so behavior
/// is identical to when they lived inline. AppColors exclusive.
extension _GenerationOptionsAdvanced on _GenerationOptionsTabState {
  List<Widget> _buildAdvancedFields(
    StorageService st, {
    required bool isDrawThings,
  }) {
    // On the Edit tab these knobs are edit-scoped so an edit never clobbers
    // Create's txt2img settings; everywhere else they are the shared knobs.
    final editScoped = widget.editScoped;
    final steps = editScoped
        ? st.imageGenSettings.editSteps
        : st.imageGenSettings.imageGenSteps;
    final cfg = editScoped
        ? st.imageGenSettings.editCfgScale
        : st.imageGenSettings.imageGenCfgScale;
    final dtSampler = editScoped
        ? st.imageGenSettings.editSampler
        : st.imageGenSettings.drawThingsSampler;
    final dtShift = editScoped
        ? st.imageGenSettings.editShift
        : st.imageGenSettings.drawThingsShift;
    final dtSeedMode = editScoped
        ? st.imageGenSettings.editSeedMode
        : st.imageGenSettings.drawThingsSeedMode;
    return [
      Row(
        children: [
          Text(
            'Steps',
            style: TextStyle(
              color: AppColors.textSecondary(context),
              fontSize: 10,
            ),
          ),
          Expanded(
            child: Slider(
              value: _dragSteps ?? steps.toDouble(),
              min: 5,
              max: 50,
              divisions: 45,
              activeColor: AppColors.formMasterAccent,
              inactiveColor: AppColors.borderOf(context),
              onChanged: (v) => rebuildState(() => _dragSteps = v),
              onChangeEnd: (v) {
                _dragSteps = null;
                editScoped
                    ? st.imageGenSettings.setEditSteps(v.round())
                    : st.imageGenSettings.setImageGenSteps(v.round());
              },
            ),
          ),
          SizedBox(
            width: 26,
            child: Text(
              (_dragSteps ?? steps.toDouble()).round().toString(),
              style: TextStyle(
                color: AppColors.textSecondary(context),
                fontSize: 9,
              ),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
      Row(
        children: [
          Text(
            'CFG',
            style: TextStyle(
              color: AppColors.textSecondary(context),
              fontSize: 10,
            ),
          ),
          Expanded(
            child: Slider(
              value: _dragCfgScale ?? cfg,
              min: 1,
              max: 20,
              divisions: 190,
              activeColor: AppColors.formMasterAccent,
              inactiveColor: AppColors.borderOf(context),
              onChanged: (v) => rebuildState(() => _dragCfgScale = v),
              onChangeEnd: (v) {
                _dragCfgScale = null;
                editScoped
                    ? st.imageGenSettings.setEditCfgScale(v)
                    : st.imageGenSettings.setImageGenCfgScale(v);
              },
            ),
          ),
          SizedBox(
            width: 30,
            child: Text(
              (_dragCfgScale ?? cfg).toStringAsFixed(1),
              style: TextStyle(
                color: AppColors.textSecondary(context),
                fontSize: 9,
              ),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
      // In EDIT mode the string sampler (ComfyUI/A1111) is hidden: the ComfyUI
      // edit preset bakes its own sampler, and picking one here only clobbered
      // the Create-tab sampler while doing nothing to the edit. The DrawThings
      // int sampler stays — it IS edit-scoped (setEditSampler below).
      if (isDrawThings || !editScoped)
        Row(
          children: [
            Expanded(
              flex: 2,
              child: Text(
                'Sampler',
                style: TextStyle(
                  color: AppColors.textSecondary(context),
                  fontSize: 10,
                ),
              ),
            ),
            Expanded(
              flex: 3,
              child: isDrawThings
                  ? DropdownButtonFormField<int>(
                      initialValue: dtSampler,
                      dropdownColor: AppColors.surfaceContainerOf(context),
                      style: TextStyle(
                        color: AppColors.textPrimary(context),
                        fontSize: 10,
                      ),
                      isExpanded: true,
                      decoration: _deco(hint: 'DT'),
                      items: _drawThingsSamplers
                          .map(
                            (s) => DropdownMenuItem(
                              value: s.value,
                              child: Text(
                                s.label,
                                style: TextStyle(
                                  fontSize: 9,
                                  color: AppColors.textPrimary(context),
                                ),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (v) {
                        if (v == null) return;
                        editScoped
                            ? st.imageGenSettings.setEditSampler(v)
                            : st.imageGenSettings.setDrawThingsSampler(v);
                      },
                    )
                  : DropdownButtonFormField<String>(
                      initialValue:
                          _localSamplers.contains(
                            st.imageGenSettings.imageGenSampler,
                          )
                          ? st.imageGenSettings.imageGenSampler
                          : (st.imageGenSettings.imageGenSampler.isNotEmpty
                                ? null
                                : 'Euler a'),
                      dropdownColor: AppColors.surfaceContainerOf(context),
                      style: TextStyle(
                        color: AppColors.textPrimary(context),
                        fontSize: 10,
                      ),
                      isExpanded: true,
                      decoration: _deco(hint: 'sampler'),
                      items: _localSamplers
                          .map(
                            (s) => DropdownMenuItem(
                              value: s,
                              child: Text(
                                s,
                                style: TextStyle(
                                  fontSize: 9,
                                  color: AppColors.textPrimary(context),
                                ),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (v) {
                        if (v != null) {
                          st.imageGenSettings.setImageGenSampler(v);
                        }
                      },
                    ),
            ),
          ],
        ),
      // Scheduler (noise schedule) — a real quality lever on A1111 and ComfyUI.
      // Draw Things has no separate scheduler concept, so it's hidden there.
      // Hidden in EDIT mode too: the ComfyUI edit preset controls it, so a
      // choice here only clobbered the Create-tab scheduler (same as sampler).
      // 'Automatic' means the backend decides (A1111 default / sampler-derived
      // for ComfyUI); the fetched list is server-specific.
      if (!isDrawThings && !editScoped)
        Row(
          children: [
            Expanded(
              flex: 2,
              child: Text(
                'Scheduler',
                style: TextStyle(
                  color: AppColors.textSecondary(context),
                  fontSize: 10,
                ),
              ),
            ),
            Expanded(
              flex: 3,
              child: DropdownButtonFormField<String>(
                initialValue:
                    (st.imageGenSettings.imageGenScheduler == 'Automatic' ||
                        _localSchedulers.contains(
                          st.imageGenSettings.imageGenScheduler,
                        ))
                    ? st.imageGenSettings.imageGenScheduler
                    : 'Automatic',
                dropdownColor: AppColors.surfaceContainerOf(context),
                style: TextStyle(
                  color: AppColors.textPrimary(context),
                  fontSize: 10,
                ),
                isExpanded: true,
                decoration: _deco(hint: 'scheduler'),
                items: <String>['Automatic', ..._localSchedulers]
                    .map(
                      (s) => DropdownMenuItem(
                        value: s,
                        child: Text(
                          s,
                          style: TextStyle(
                            fontSize: 9,
                            color: AppColors.textPrimary(context),
                          ),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v != null) st.imageGenSettings.setImageGenScheduler(v);
                },
              ),
            ),
          ],
        ),
      Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              'Seed',
              style: TextStyle(
                color: AppColors.textSecondary(context),
                fontSize: 10,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _seedController,
                    style: TextStyle(
                      color: AppColors.textPrimary(context),
                      fontSize: 10,
                    ),
                    keyboardType: TextInputType.number,
                    decoration: _deco(hint: '-1=random'),
                    onChanged: (v) {
                      st.imageGenSettings.setImageGenSeed(
                        int.tryParse(v) ?? -1,
                      );
                    },
                  ),
                ),
                IconButton(
                  icon: Icon(
                    Icons.casino_outlined,
                    size: 14,
                    color: AppColors.formMasterAccent,
                  ),
                  onPressed: _randomizeSeed,
                ),
              ],
            ),
          ),
        ],
      ),
      if (isDrawThings) ...[
        const SizedBox(height: 6),
        Text(
          'DT Advanced',
          style: TextStyle(
            color: AppColors.textSecondary(context),
            fontSize: 9,
            fontWeight: FontWeight.w600,
          ),
        ),
        Row(
          children: [
            Text(
              'Shift',
              style: TextStyle(
                color: AppColors.textSecondary(context),
                fontSize: 9,
              ),
            ),
            Expanded(
              child: Slider(
                value: dtShift,
                min: 0,
                max: 10,
                divisions: 100,
                activeColor: AppColors.formMasterAccent,
                onChanged: (v) => editScoped
                    ? st.imageGenSettings.setEditShift(v)
                    : st.imageGenSettings.setDrawThingsShift(v),
              ),
            ),
            SizedBox(
              width: 24,
              child: Text(
                dtShift.toStringAsFixed(1),
                style: TextStyle(fontSize: 8),
                textAlign: TextAlign.end,
              ),
            ),
          ],
        ),
        Row(
          children: [
            Text(
              'SeedMode',
              style: TextStyle(
                color: AppColors.textSecondary(context),
                fontSize: 9,
              ),
            ),
            DropdownButton<int>(
              value: dtSeedMode,
              style: TextStyle(fontSize: 9),
              items: const [
                DropdownMenuItem(
                  value: 0,
                  child: Text('Rand', style: TextStyle(fontSize: 8)),
                ),
                DropdownMenuItem(
                  value: 1,
                  child: Text('Const', style: TextStyle(fontSize: 8)),
                ),
                DropdownMenuItem(
                  value: 2,
                  child: Text('PerImg', style: TextStyle(fontSize: 8)),
                ),
                DropdownMenuItem(
                  value: 3,
                  child: Text('Prompt', style: TextStyle(fontSize: 8)),
                ),
              ],
              onChanged: (v) {
                if (v == null) return;
                editScoped
                    ? st.imageGenSettings.setEditSeedMode(v)
                    : st.imageGenSettings.setDrawThingsSeedMode(v);
              },
            ),
            Checkbox(
              value: st.imageGenSettings.drawThingsTeaCache,
              onChanged: (v) =>
                  st.imageGenSettings.setDrawThingsTeaCache(v ?? false),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            Text('Tea', style: TextStyle(fontSize: 8)),
            Checkbox(
              value: st.imageGenSettings.drawThingsCfgZeroStar,
              onChanged: (v) =>
                  st.imageGenSettings.setDrawThingsCfgZeroStar(v ?? false),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            Text('Zero', style: TextStyle(fontSize: 8)),
          ],
        ),
      ],
    ];
  }
}
