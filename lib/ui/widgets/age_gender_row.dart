import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/creator_palette.dart';
import 'app_text_field.dart';

class AgeGenderRow extends StatelessWidget {
  const AgeGenderRow({
    super.key,
    required this.ageController,
    required this.genderController,
    this.onChanged,
    this.ageLabel = 'Age',
    this.genderLabel = 'Gender',
    this.ageHint = 'e.g. 25, Ancient...',
    this.genderHint = 'e.g. Female, Male...',
  });

  final TextEditingController ageController;
  final TextEditingController genderController;
  final VoidCallback? onChanged;
  final String ageLabel;
  final String genderLabel;
  final String ageHint;
  final String genderHint;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _field(context, ageLabel, ageController, ageHint)),
        const SizedBox(width: 12),
        Expanded(
          child: _field(context, genderLabel, genderController, genderHint),
        ),
      ],
    );
  }

  /// One labelled box: the app's look, or the spec's Field and label inside
  /// the AI Character Creator.
  Widget _field(
    BuildContext context,
    String label,
    TextEditingController controller,
    String hint,
  ) {
    final p = CreatorPalette.maybeOf(context);
    OutlineInputBorder outline(Color c) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: c),
    );
    final line = p?.fieldBorder ?? AppColors.borderOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          p != null ? label.toUpperCase() : label,
          style:
              p?.labelStyle ??
              TextStyle(
                color: AppColors.textPrimary(context),
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
        ),
        SizedBox(height: p == null ? 8 : 6),
        AppTextField(
          controller: controller,
          onChanged: (_) => onChanged?.call(),
          style: TextStyle(
            color: p?.ink ?? AppColors.textPrimary(context),
            fontSize: 14,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
              color: p?.faint ?? AppColors.textTertiary(context),
              fontSize: p == null ? 13 : 14,
            ),
            filled: true,
            fillColor: p?.fieldFill ?? AppColors.surfaceContainerOf(context),
            border: outline(line),
            enabledBorder: outline(line),
            focusedBorder: outline(p?.amber ?? AppColors.formAccentOf(context)),
            contentPadding: p == null
                ? const EdgeInsets.symmetric(horizontal: 16, vertical: 14)
                : const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          ),
          maxLines: 1,
        ),
      ],
    );
  }
}
