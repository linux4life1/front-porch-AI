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

part of 'world_management_page.dart';

/// Basic Information card for the create/edit World dialog: cover
/// image (picker + thumbnail), name/description fields, and the
/// inject-description toggle + place traits editor. The Climate picker is
/// extracted separately (world_management_page.climate.dart) and embedded
/// here at the same position it occupied before this split.
///
/// [ctx] is the dialog's StatefulBuilder context (styling, nested
/// dialogs); [pageContext] is the original `_showWorldDialog` context --
/// kept separate because the cover-image error SnackBar was already
/// anchored to the page scaffold rather than the dialog before this
/// split, and that is preserved verbatim.
extension _WorldBasicsSection on _WorldManagementPageState {
  Widget _buildBasicsSection(
    BuildContext ctx,
    BuildContext pageContext,
    _WorldDraft draft,
    StateSetter setDialogState, {
    bool compact = false,
  }) {
    final gap = compact ? 8.0 : 16.0;
    final pad = compact ? 8.0 : 20.0;
    final thumb = compact ? 56.0 : 72.0;
    return Container(
      padding: EdgeInsets.all(pad),
      decoration: BoxDecoration(
        color: AppColors.resolve(
          ctx,
          AppColors.surfaceContainer.withValues(alpha: 0.3),
          AppColors.surfaceContainerLight.withValues(alpha: 0.6),
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.borderOf(ctx).withValues(alpha: 0.2),
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
                color: AppColors.formMasterAccent,
              ),
              const SizedBox(width: 8),
              Text(
                'Basic Information',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary(ctx),
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
                  child: _coverThumb(ctx, draft.coverImage),
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
                        color: AppColors.textSecondary(ctx),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Shown on the Worlds grid and packed into .fpworld. Required to share on the Stoop.',
                      style: TextStyle(
                        fontSize: 10.5,
                        color: AppColors.textTertiary(ctx),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        TextButton.icon(
                          onPressed: () async {
                            final bytes = await pickImageBytes();
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
                            foregroundColor: AppColors.formMasterAccent,
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
                                color: AppColors.textTertiary(ctx),
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
            style: TextStyle(color: AppColors.textPrimary(ctx)),
            decoration: InputDecoration(
              labelText: 'World Name',
              labelStyle: TextStyle(color: AppColors.textSecondary(ctx)),
              hintText: 'Enter a name for this world',
              hintStyle: TextStyle(color: AppColors.textTertiary(ctx)),
              filled: true,
              fillColor: AppColors.surfaceContainerOf(ctx),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: AppColors.borderOf(ctx)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: AppColors.borderOf(ctx)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(
                  color: AppColors.formMasterAccent,
                  width: 1.5,
                ),
              ),
              contentPadding: const EdgeInsets.all(16),
            ),
          ),
          SizedBox(height: gap),
          TextField(
            controller: draft.descController,
            style: TextStyle(color: AppColors.textPrimary(ctx)),
            maxLines: compact ? 2 : 3,
            decoration: InputDecoration(
              labelText: 'Description (place prose)',
              labelStyle: TextStyle(color: AppColors.textSecondary(ctx)),
              hintText:
                  'What it feels like to be here — reaches the story when enabled',
              hintStyle: TextStyle(color: AppColors.textTertiary(ctx)),
              filled: true,
              fillColor: AppColors.surfaceContainerOf(ctx),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: AppColors.borderOf(ctx)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: AppColors.borderOf(ctx)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(
                  color: AppColors.formMasterAccent,
                  width: 1.5,
                ),
              ),
              contentPadding: EdgeInsets.all(compact ? 12 : 16),
            ),
          ),
          SizedBox(height: gap),
          _draftSwitch(
            ctx,
            title: 'Climate, weather, and place traits',
            subtitle:
                'Off = lorebook and description only — no forecast, '
                'no atmosphere or gravity',
            value: draft.climateEnabled,
            onChanged: (v) => setDialogState(() => draft.climateEnabled = v),
          ),
          if (draft.climateEnabled) ...[
            const SizedBox(height: 8),
            _buildClimateSection(ctx, draft, setDialogState),
          ],
          const SizedBox(height: 12),
          _draftSwitch(
            ctx,
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
    BuildContext ctx, {
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
                  color: AppColors.textPrimary(ctx),
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  color: AppColors.textTertiary(ctx),
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
        Switch(
          value: value,
          activeThumbColor: AppColors.formMasterAccent,
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
      color: AppColors.formMasterAccent.withValues(alpha: 0.12),
      child: Icon(
        Icons.public,
        color: AppColors.formMasterAccent.withValues(alpha: 0.7),
        size: 28,
      ),
    );
  }
}
