import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
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
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _inputLabel(context, ageLabel),
              const SizedBox(height: 8),
              AppTextField(
                controller: ageController,
                onChanged: (_) => onChanged?.call(),
                style: TextStyle(
                  color: AppColors.textPrimary(context),
                  fontSize: 14,
                ),
                decoration: InputDecoration(
                  hintText: ageHint,
                  hintStyle: TextStyle(color: AppColors.textTertiary(context), fontSize: 13),
                  filled: true,
                  fillColor: AppColors.surfaceContainerOf(context),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: AppColors.borderOf(context)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: AppColors.borderOf(context)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Colors.blueAccent),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
                maxLines: 1,
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _inputLabel(context, genderLabel),
              const SizedBox(height: 8),
              AppTextField(
                controller: genderController,
                onChanged: (_) => onChanged?.call(),
                style: TextStyle(
                  color: AppColors.textPrimary(context),
                  fontSize: 14,
                ),
                decoration: InputDecoration(
                  hintText: genderHint,
                  hintStyle: TextStyle(color: AppColors.textTertiary(context), fontSize: 13),
                  filled: true,
                  fillColor: AppColors.surfaceContainerOf(context),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: AppColors.borderOf(context)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: AppColors.borderOf(context)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Colors.blueAccent),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
                maxLines: 1,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

Widget _inputLabel(BuildContext context, String text) {
  return Text(
    text,
    style: TextStyle(
      color: AppColors.textPrimary(context),
      fontSize: 15,
      fontWeight: FontWeight.w600,
    ),
  );
}
