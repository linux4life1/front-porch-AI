import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/creator_palette.dart';
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
    // Inside the AI Character Creator the spec's Field and label; the app's
    // own look everywhere else.
    final p = CreatorPalette.maybeOf(context);
    OutlineInputBorder outline(Color c) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: c),
    );
    final line = p?.fieldBorder ?? AppColors.borderOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _inputLabel(context, p, label, required: required),
            const Spacer(),
            Tooltip(
              message: tooltip,
              child: IconButton(
                icon: Icon(
                  Icons.casino,
                  color: p?.iconAccent ?? Colors.amberAccent,
                  size: 20,
                ),
                onPressed: onRandomize,
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
        ),
        SizedBox(height: p == null ? 8 : 6),
        AppTextField(
          controller: controller,
          onChanged: onChanged,
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
            focusedBorder: outline(p?.amber ?? AppColors.formMasterAccent),
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

Widget _inputLabel(
  BuildContext context,
  CreatorPalette? p,
  String text, {
  bool required = false,
}) {
  final style = p != null
      ? p.labelStyle
      : TextStyle(
          color: AppColors.textPrimary(context),
          fontSize: 15,
          fontWeight: FontWeight.w600,
        );
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(p != null ? text.toUpperCase() : text, style: style),
      if (required)
        Text(
          ' *',
          style: style.copyWith(
            color:
                p?.amber ??
                AppColors.resolve(
                  context,
                  Colors.redAccent,
                  Colors.red.shade700,
                ),
          ),
        ),
    ],
  );
}
