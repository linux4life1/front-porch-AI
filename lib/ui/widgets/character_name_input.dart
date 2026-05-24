import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'app_text_field.dart';

class CharacterNameInput extends StatelessWidget {
  const CharacterNameInput({
    super.key,
    required this.controller,
    required this.onRandomize,
    this.onChanged,
    this.tooltip = 'Generate a random name',
    this.label = 'Character Name',
    this.required = true,
    this.hint = 'e.g. Aria Blackwood, Captain Zara, Luna...',
  });

  final TextEditingController controller;
  final VoidCallback onRandomize;
  final ValueChanged<String>? onChanged;
  final String tooltip;
  final String label;
  final bool required;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _inputLabel(context, label, required: required),
            const Spacer(),
            Tooltip(
              message: tooltip,
              child: IconButton(
                icon: Icon(
                  Icons.casino,
                  color: Colors.amberAccent,
                  size: 20,
                ),
                onPressed: onRandomize,
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        AppTextField(
          controller: controller,
          onChanged: onChanged,
          style: TextStyle(
            color: AppColors.textPrimary(context),
            fontSize: 14,
          ),
          decoration: InputDecoration(
            hintText: hint,
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
    );
  }
}

Widget _inputLabel(BuildContext context, String text, {bool required = false}) {
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        text,
        style: TextStyle(
          color: AppColors.textPrimary(context),
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
      if (required)
        Text(
          ' *',
          style: TextStyle(
            color: AppColors.resolve(context, Colors.redAccent, Colors.red.shade700),
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
    ],
  );
}
