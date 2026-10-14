import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/creator_palette.dart';

class StyledDropdown<T> extends StatelessWidget {
  const StyledDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.width,
  });

  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final double? width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color:
              context.creatorPalette?.raise ??
              AppColors.surfaceContainerOf(context),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: context.creatorPalette?.line ?? AppColors.borderOf(context),
          ),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<T>(
            value: value,
            isExpanded: true,
            dropdownColor:
                context.creatorPalette?.raise ??
                AppColors.surfaceContainerOf(context),
            style: TextStyle(
              color:
                  context.creatorPalette?.ink ?? AppColors.textPrimary(context),
              fontSize: 13,
            ),
            items: items,
            onChanged: onChanged,
          ),
        ),
      ),
    );
  }
}
