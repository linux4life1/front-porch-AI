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

/// The fields shared by every backend (prompt review toggle, size chips,
/// default style/paradigm, negative prompt, Advanced gate) for
/// [_GenerationOptionsTabState], split out of the shell to keep every file
/// under the 500-LOC cap (mirrors the settings_page.dart `part of` pattern).
/// These methods keep direct access to the tab's private state, so behavior
/// is identical to when they lived inline. AppColors exclusive.
extension _GenerationOptionsSharedFields on _GenerationOptionsTabState {
  Widget _buildSharedFields(StorageService st) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          title: Text(
            'Review AI prompts before generating',
            style: TextStyle(
              color: AppColors.textPrimary(context),
              fontSize: 12,
            ),
          ),
          subtitle: Text(
            '/image pauses so you can edit the crafted prompt first',
            style: TextStyle(
              color: AppColors.textTertiary(context),
              fontSize: 10,
            ),
          ),
          value: st.imageGenSettings.imageGenPromptReview,
          activeTrackColor: AppColors.formMasterAccent,
          contentPadding: EdgeInsets.zero,
          dense: true,
          onChanged: (v) => st.imageGenSettings.setImageGenPromptReview(v),
        ),
        const SizedBox(height: 4),
        Text(
          'Image Size',
          style: TextStyle(
            color: AppColors.textSecondary(context),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        _buildSizeSelector(st),
        const SizedBox(height: 8),
        if (widget.showStyleControls) ...[
          Text(
            'Default Style',
            style: TextStyle(
              color: AppColors.textSecondary(context),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          DropdownButtonFormField<String>(
            initialValue:
                ImageGenService.styleLabels.containsKey(
                  st.imageGenSettings.imageGenStyle,
                )
                ? st.imageGenSettings.imageGenStyle
                : 'photorealistic',
            dropdownColor: AppColors.surfaceContainerOf(context),
            style: TextStyle(color: AppColors.textPrimary(context)),
            isExpanded: true,
            decoration: _deco(),
            items: ImageGenService.styleLabels.entries
                .map(
                  (e) => DropdownMenuItem(
                    value: e.key,
                    child: Text(
                      e.value,
                      style: TextStyle(color: AppColors.textPrimary(context)),
                    ),
                  ),
                )
                .toList(),
            onChanged: (v) {
              if (v != null) st.imageGenSettings.setImageGenStyle(v);
            },
          ),
          const SizedBox(height: 6),
          Text(
            'Prompt Format',
            style: TextStyle(
              color: AppColors.textSecondary(context),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          DropdownButtonFormField<String>(
            initialValue: st.imageGenSettings.imageGenPromptParadigm,
            dropdownColor: AppColors.surfaceContainerOf(context),
            style: TextStyle(color: AppColors.textPrimary(context)),
            isExpanded: true,
            decoration: _deco(),
            items: const [
              DropdownMenuItem(
                value: 'natural',
                child: Text('Natural Language (FLUX / SD3)'),
              ),
              DropdownMenuItem(
                value: 'tags',
                child: Text('Danbooru Tags (SD 1.5 / Anime)'),
              ),
            ],
            onChanged: (v) {
              if (v != null) st.imageGenSettings.setImageGenPromptParadigm(v);
            },
          ),
        ],
        const SizedBox(height: 6),
        Text(
          'Default Negative Prompt',
          style: TextStyle(
            color: AppColors.textSecondary(context),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        TextField(
          controller: _negativePromptController,
          maxLines: 2,
          style: TextStyle(color: AppColors.textPrimary(context), fontSize: 12),
          decoration: _deco(hint: 'e.g. blurry...'),
          onChanged: (v) => st.imageGenSettings.setImageGenNegativePrompt(v),
        ),
        const SizedBox(height: 8),
        Consumer<StorageService>(
          builder: (ctx, st2, c) {
            final local = st2.imageGenSettings.imageGenBackend != 'remote';
            return ExpansionTile(
              title: Text(
                'Advanced',
                style: TextStyle(
                  color: AppColors.textSecondary(context),
                  fontSize: 12,
                ),
              ),
              tilePadding: EdgeInsets.zero,
              children: local
                  ? _buildAdvancedFields(
                      st2,
                      isDrawThings:
                          st2.imageGenSettings.imageGenBackend == 'drawthings',
                    )
                  : [
                      Text(
                        'Local backend required.',
                        style: TextStyle(
                          color: AppColors.textTertiary(context),
                          fontSize: 10,
                        ),
                      ),
                    ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildSizeSelector(StorageService st) {
    const sizes = ['512x512', '768x768', '1024x1024', '1536x1024', '1024x1536'];
    const labels = ['512²', '768²', '1024²', '1536×1024', '1024×1536'];
    final ac = AppColors.formMasterAccent;
    final kids = <Widget>[];
    for (var i = 0; i < sizes.length; i++) {
      final sel = st.imageGenSettings.imageGenSize == sizes[i];
      kids.add(
        GestureDetector(
          onTap: () => st.imageGenSettings.setImageGenSize(sizes[i]),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: sel
                  ? AppColors.cardOf(context)
                  : AppColors.surfaceContainerOf(context),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: sel ? ac : AppColors.borderOf(context)),
            ),
            child: Text(
              labels[i],
              style: TextStyle(
                color: sel ? ac : AppColors.textSecondary(context),
                fontSize: 10,
                fontWeight: sel ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ),
      );
    }
    return Wrap(spacing: 6, children: kids);
  }
}
