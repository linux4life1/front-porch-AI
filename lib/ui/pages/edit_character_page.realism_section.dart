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
// The character editor's Realism section (engine toggles + seeds).
// Extracted verbatim from edit_character_page.dart (god-file campaign,
// Tranche A); `part of` the same library — privates stay in scope.

part of 'edit_character_page.dart';

extension _EditCharacterRealismSection on _EditCharacterPageState {
  Widget _buildRealismSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Playful disclaimer note
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.formMasterAccent.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppColors.formMasterAccent.withValues(alpha: 0.2),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('😉', style: TextStyle(fontSize: 18)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'These settings only affect new conversations with this character — '
                  'your existing chats won\'t be changed. No cheating with the relationship values!',
                  style: TextStyle(
                    color: AppColors.formMasterAccent.withValues(alpha: 0.8),
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Full editable Realism Engine form
        RealismFormSection(
          enabled: _realismEnabled,
          onEnabledChanged: (v) => rebuildState(() {
            _realismEnabled = v;
            _realismSettingsModified = true;
          }),
          timeOfDay: _realismTimeOfDay,
          onTimeOfDayChanged: (v) => rebuildState(() {
            _realismTimeOfDay = v;
            _realismSettingsModified = true;
          }),
          dayCount: _realismDayCount,
          onDayCountChanged: (v) => rebuildState(() {
            _realismDayCount = v;
            _realismSettingsModified = true;
          }),
          storyStartDate: _realismStoryStartDate,
          onStoryStartDateChanged: (v) => rebuildState(() {
            _realismStoryStartDate = v;
            _realismSettingsModified = true;
          }),
          storyStartTime: _realismStoryStartTime,
          onStoryStartTimeChanged: (v) => rebuildState(() {
            _realismStoryStartTime = v;
            _realismSettingsModified = true;
          }),
          shortTermBond: _realismShortTermBond,
          onShortTermBondChanged: (v) => rebuildState(() {
            _realismShortTermBond = v;
            _realismSettingsModified = true;
          }),
          longTermBond: _realismLongTermBond,
          onLongTermBondChanged: (v) => rebuildState(() {
            _realismLongTermBond = v;
            _realismSettingsModified = true;
          }),
          trustLevel: _realismTrustLevel,
          onTrustLevelChanged: (v) => rebuildState(() {
            _realismTrustLevel = v;
            _realismSettingsModified = true;
          }),
          emotion: _realismEmotion,
          onEmotionChanged: (v) => rebuildState(() {
            _realismEmotion = v;
            _realismSettingsModified = true;
          }),
          emotionIntensity: _realismEmotionIntensity,
          onEmotionIntensityChanged: (v) => rebuildState(() {
            _realismEmotionIntensity = v;
            _realismSettingsModified = true;
          }),
          nsfwCooldownEnabled: _realismNsfwCooldown,
          onNsfwCooldownChanged: (v) => rebuildState(() {
            _realismNsfwCooldown = v;
            _realismSettingsModified = true;
          }),
          chaosModeEnabled: _realismChaosMode,
          onChaosModeChanged: (v) => rebuildState(() {
            _realismChaosMode = v;
            _realismSettingsModified = true;
          }),
          realismVerificationEnabled: _realismVerificationEnabled,
          onRealismVerificationChanged: (v) => rebuildState(() {
            _realismVerificationEnabled = v;
            _realismSettingsModified = true;
          }),
          realismVerificationMaxReprocesses: _realismVerificationMaxReprocesses,
          onRealismVerificationMaxReprocessesChanged: (v) => rebuildState(() {
            _realismVerificationMaxReprocesses = v;
            _realismSettingsModified = true;
          }),
          realismVerificationStrictness: _realismVerificationStrictness,
          onRealismVerificationStrictnessChanged: (v) => rebuildState(() {
            _realismVerificationStrictness = v;
            _realismSettingsModified = true;
          }),
          needsFormSection: NeedsFormSection(
            enabled: _realismNeedsSim,
            onEnabledChanged: (v) => rebuildState(() {
              _realismNeedsSim = v;
              _realismSettingsModified = true;
            }),
            enjoysLowHygiene: _realismEnjoysLowHygiene,
            onEnjoysLowHygieneChanged: (v) => rebuildState(() {
              _realismEnjoysLowHygiene = v;
              _realismSettingsModified = true;
            }),
            needsSimStrength: _needsSimStrength,
            onNeedsSimStrengthChanged: (v) => rebuildState(() {
              _needsSimStrength = v;
              _realismSettingsModified = true;
            }),
            baselineHunger: _needsBaselineHunger,
            onBaselineHungerChanged: (v) => rebuildState(() {
              _needsBaselineHunger = v;
              _realismSettingsModified = true;
            }),
            baselineBladder: _needsBaselineBladder,
            onBaselineBladderChanged: (v) => rebuildState(() {
              _needsBaselineBladder = v;
              _realismSettingsModified = true;
            }),
            baselineEnergy: _needsBaselineEnergy,
            onBaselineEnergyChanged: (v) => rebuildState(() {
              _needsBaselineEnergy = v;
              _realismSettingsModified = true;
            }),
            baselineSocial: _needsBaselineSocial,
            onBaselineSocialChanged: (v) => rebuildState(() {
              _needsBaselineSocial = v;
              _realismSettingsModified = true;
            }),
            baselineFun: _needsBaselineFun,
            onBaselineFunChanged: (v) => rebuildState(() {
              _needsBaselineFun = v;
              _realismSettingsModified = true;
            }),
            baselineHygiene: _needsBaselineHygiene,
            onBaselineHygieneChanged: (v) => rebuildState(() {
              _needsBaselineHygiene = v;
              _realismSettingsModified = true;
            }),
            baselineComfort: _needsBaselineComfort,
            onBaselineComfortChanged: (v) => rebuildState(() {
              _needsBaselineComfort = v;
              _realismSettingsModified = true;
            }),
            decayHunger: _needsDecayHunger,
            onDecayHungerChanged: (v) => rebuildState(() {
              _needsDecayHunger = v;
              _realismSettingsModified = true;
            }),
            decayBladder: _needsDecayBladder,
            onDecayBladderChanged: (v) => rebuildState(() {
              _needsDecayBladder = v;
              _realismSettingsModified = true;
            }),
            decayEnergy: _needsDecayEnergy,
            onDecayEnergyChanged: (v) => rebuildState(() {
              _needsDecayEnergy = v;
              _realismSettingsModified = true;
            }),
            decaySocial: _needsDecaySocial,
            onDecaySocialChanged: (v) => rebuildState(() {
              _needsDecaySocial = v;
              _realismSettingsModified = true;
            }),
            decayFun: _needsDecayFun,
            onDecayFunChanged: (v) => rebuildState(() {
              _needsDecayFun = v;
              _realismSettingsModified = true;
            }),
            decayHygiene: _needsDecayHygiene,
            onDecayHygieneChanged: (v) => rebuildState(() {
              _needsDecayHygiene = v;
              _realismSettingsModified = true;
            }),
            decayComfort: _needsDecayComfort,
            onDecayComfortChanged: (v) => rebuildState(() {
              _needsDecayComfort = v;
              _realismSettingsModified = true;
            }),
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  SHARED WIDGETS
  // ═══════════════════════════════════════════════════════════════

  /// Glassmorphic section card with icon header.
  Widget _sectionCard({
    required IconData icon,
    required String title,
    required Color color,
    required List<Widget> children,
    Widget? trailing,
    bool collapsed = false,
  }) {
    final header = Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: TextStyle(
            color: color,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (trailing != null) ...[const Spacer(), trailing],
      ],
    );

    if (collapsed) {
      // Material, not a decorated Container: ExpansionTile's header is a
      // ListTile, which paints its background and ink splash onto the nearest
      // Material ancestor — a coloured DecoratedBox in between swallows the
      // ripple. Flutter 3.44 asserts on this ("ListTile background color or
      // ink splashes may be invisible"). Same colour, radius and border; the
      // header ripple now actually renders.
      return Material(
        color: AppColors.cardOf(context),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: AppColors.borderOf(context).withValues(alpha: 0.45),
          ),
        ),
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 4,
            ),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            leading: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            title: Text(
              title,
              style: TextStyle(
                color: color,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            iconColor: AppColors.iconSecondary(context),
            collapsedIconColor: AppColors.iconSecondary(context),
            children: children,
          ),
        ),
      );
    }

    // Same Material surface as the collapsed ExpansionTile path — Alternate
    // Greetings (and any other section) can host ListTiles/SwitchListTiles,
    // and a coloured DecoratedBox between them and the scaffold Material
    // trips Flutter's "ink may be invisible" assert.
    return Material(
      color: AppColors.cardOf(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: AppColors.borderOf(context).withValues(alpha: 0.45),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [header, const SizedBox(height: 16), ...children],
        ),
      ),
    );
  }

  /// Styled text field matching the manual creator design.
  Widget _styledField({
    required TextEditingController controller,
    required String label,
    int maxLines = 1,
    bool expandable = false,
    bool enabled = true,
    String? hint,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _fieldLabel(label),
            if (expandable) ...[
              const SizedBox(width: 8),
              InkWell(
                onTap: () => showExpandedEditorDialog(
                  context: context,
                  title: label,
                  controller: controller,
                  hintText: 'Enter $label...',
                ),
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Tooltip(
                    message: 'Open fullscreen editor',
                    child: Icon(
                      Icons.open_in_full,
                      size: 14,
                      color: AppColors.resolve(
                        context,
                        Colors.white.withValues(alpha: 0.25),
                        Colors.black.withValues(alpha: 0.25),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        AppTextField(
          controller: controller,
          maxLines: maxLines,
          enabled: enabled,
          style: TextStyle(
            color: enabled
                ? AppColors.textPrimary(context)
                : AppColors.textTertiary(context),
            fontSize: 14,
          ),
          decoration: _inputDecoration(hint ?? 'Enter $label...'),
        ),
      ],
    );
  }

  Widget _fieldLabel(String text) {
    return Text(
      text,
      style: TextStyle(
        color: AppColors.textSecondary(context),
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(
        color: AppColors.textTertiary(context),
        fontSize: 13,
      ),
      filled: true,
      fillColor: AppColors.backgroundOf(context),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(
          color: AppColors.borderOf(context).withValues(alpha: 0.45),
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(
          color: AppColors.borderOf(context).withValues(alpha: 0.45),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _borderFocus),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(
          color: AppColors.resolve(
            context,
            Colors.white.withValues(alpha: 0.04),
            Colors.black.withValues(alpha: 0.04),
          ),
        ),
      ),
      contentPadding: const EdgeInsets.all(14),
    );
  }
}
