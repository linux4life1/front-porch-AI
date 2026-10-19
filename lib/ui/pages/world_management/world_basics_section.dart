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

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:front_porch_ai/ui/dialogs/avatar_gallery/avatar_gallery_io.dart';
import 'package:front_porch_ai/ui/pages/worlds/worlds.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/utils/world_cover.dart';
import 'world_climate_section.dart';
import 'world_edit_draft.dart';

/// Basic Information card for the create/edit World dialog: cover
/// image (picker + thumbnail), name/description fields, the climate
/// toggle + [WorldClimateSection], the inject-description toggle, and the
/// place traits editor.
///
/// [pageContext] is the context the dialog was opened from: the
/// cover-image error SnackBar is anchored to the page scaffold rather
/// than the dialog. [pickerContext] is the page context the image picker
/// runs on.
class WorldBasicsSection extends StatelessWidget {
  const WorldBasicsSection({
    super.key,
    required this.pageContext,
    required this.pickerContext,
    required this.draft,
    required this.setDialogState,
    this.compact = false,
  });

  final BuildContext pageContext;
  final BuildContext pickerContext;
  final WorldEditDraft draft;
  final StateSetter setDialogState;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final gap = compact ? 8.0 : 16.0;
    final pad = compact ? 8.0 : 20.0;
    final thumb = compact ? 56.0 : 72.0;
    return Container(
      padding: EdgeInsets.all(pad),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerOf(
          context,
        ).withValues(alpha: AppColors.isLight(context) ? 0.6 : 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.borderOf(context).withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.info_outline,
                size: 18,
                color: AppColors.formAccentOf(context),
              ),
              const SizedBox(width: 8),
              Text(
                'Basic Information',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary(context),
                ),
              ),
            ],
          ),
          SizedBox(height: gap),
          // Place cover (thumbnail on the Worlds grid; required on Stoop).
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: thumb,
                  height: thumb,
                  child: _coverThumb(context, draft.coverImage),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Cover image',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary(context),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Shown on the Worlds grid and packed into .fpworld. Required to share on the Stoop.',
                      style: TextStyle(
                        fontSize: 10.5,
                        color: AppColors.textTertiary(context),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        TextButton.icon(
                          onPressed: () async {
                            final bytes = await pickImageBytes(pickerContext);
                            if (bytes == null) return;
                            // Decode+resize+JPEG of a
                            // multi-MB photo — off the UI
                            // thread or the app freezes.
                            final encoded = await compute(
                              encodeWorldCoverDataUrl,
                              bytes,
                            );
                            if (encoded == null) {
                              if (pageContext.mounted) {
                                ScaffoldMessenger.of(pageContext).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Could not use that image (unsupported or too large).',
                                    ),
                                  ),
                                );
                              }
                              return;
                            }
                            setDialogState(() => draft.coverImage = encoded);
                          },
                          icon: const Icon(Icons.image_outlined, size: 16),
                          label: const Text('Choose…'),
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.formAccentOf(context),
                          ),
                        ),
                        if (draft.coverImage != null &&
                            draft.coverImage!.isNotEmpty)
                          TextButton(
                            onPressed: () =>
                                setDialogState(() => draft.coverImage = null),
                            child: Text(
                              'Remove',
                              style: TextStyle(
                                color: AppColors.textTertiary(context),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: gap),
          TextField(
            controller: draft.nameController,
            style: TextStyle(color: AppColors.textPrimary(context)),
            onChanged: (_) {
              if (draft.nameError != null) {
                setDialogState(() => draft.nameError = null);
              }
            },
            decoration: InputDecoration(
              labelText: 'World Name',
              errorText: draft.nameError,
              labelStyle: TextStyle(color: AppColors.textSecondary(context)),
              hintText: 'Enter a name for this world',
              hintStyle: TextStyle(color: AppColors.textTertiary(context)),
              filled: true,
              fillColor: AppColors.surfaceContainerOf(context),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: AppColors.borderOf(context)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: AppColors.borderOf(context)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: AppColors.formAccentOf(context),
                  width: 1.5,
                ),
              ),
              contentPadding: const EdgeInsets.all(16),
            ),
          ),
          SizedBox(height: gap),
          TextField(
            controller: draft.descController,
            style: TextStyle(color: AppColors.textPrimary(context)),
            maxLines: compact ? 2 : 3,
            decoration: InputDecoration(
              labelText: 'Description (place prose)',
              labelStyle: TextStyle(color: AppColors.textSecondary(context)),
              hintText:
                  'What it feels like to be here — reaches the story when enabled',
              hintStyle: TextStyle(color: AppColors.textTertiary(context)),
              filled: true,
              fillColor: AppColors.surfaceContainerOf(context),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: AppColors.borderOf(context)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: AppColors.borderOf(context)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: AppColors.formAccentOf(context),
                  width: 1.5,
                ),
              ),
              contentPadding: EdgeInsets.all(compact ? 12 : 16),
            ),
          ),
          SizedBox(height: gap),
          _draftSwitch(
            context,
            title: 'Climate, weather, and place traits',
            subtitle:
                'Off = lorebook and description only — no forecast, '
                'no atmosphere or gravity',
            value: draft.climateEnabled,
            onChanged: (v) => setDialogState(() => draft.climateEnabled = v),
          ),
          if (draft.climateEnabled) ...[
            const SizedBox(height: 8),
            WorldClimateSection(draft: draft, setDialogState: setDialogState),
          ],
          const SizedBox(height: 12),
          _draftSwitch(
            context,
            title: 'Inject description into story',
            subtitle: 'Place prose reaches the model each turn',
            value: draft.injectDescription,
            onChanged: (v) => setDialogState(() => draft.injectDescription = v),
          ),
          if (draft.climateEnabled) ...[
            const SizedBox(height: 16),
            PlaceTraitsEditor(
              atmosphere: draft.atmosphere,
              gravity: draft.gravity,
              onAtmosphere: (v) => setDialogState(() => draft.atmosphere = v),
              onGravity: (v) => setDialogState(() => draft.gravity = v),
            ),
          ],
        ],
      ),
    );
  }

  /// Row+Switch (not SwitchListTile): ListTile ink paints on the nearest
  /// Material, and this section sits inside a DecoratedBox fill.
  Widget _draftSwitch(
    BuildContext context, {
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: AppColors.textPrimary(context),
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  color: AppColors.textTertiary(context),
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
        Switch(
          value: value,
          activeThumbColor: AppColors.formAccentOf(context),
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _coverThumb(BuildContext context, String? coverImage) {
    final bytes = decodeWorldCoverBytes(coverImage);
    if (bytes != null) {
      return Image.memory(
        bytes,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _coverPlaceholder(context),
      );
    }
    return _coverPlaceholder(context);
  }

  Widget _coverPlaceholder(BuildContext context) {
    return ColoredBox(
      color: AppColors.formAccentOf(context).withValues(alpha: 0.12),
      child: Icon(
        Icons.public,
        color: AppColors.formAccentOf(context).withValues(alpha: 0.7),
        size: 28,
      ),
    );
  }
}
