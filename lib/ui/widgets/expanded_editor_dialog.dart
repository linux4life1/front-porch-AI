import 'package:flutter/material.dart';

import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/app_text_field.dart';
import 'package:front_porch_ai/ui/widgets/styled_text_controller.dart';

Future<void> showExpandedEditorDialog({
  required BuildContext context,
  required String title,
  required TextEditingController controller,
  String hintText = '',
}) async {
  final TextEditingController expandedController;
  if (controller is StyledTextController) {
    expandedController = StyledTextController(
      text: controller.text,
      preset: controller.preset,
    );
  } else {
    expandedController = TextEditingController(text: controller.text);
  }

  await showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => Dialog(
      insetPadding: const EdgeInsets.all(16),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      backgroundColor: AppColors.surfaceOf(ctx),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: SizedBox(
        width: double.infinity,
        height: double.infinity,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerOf(ctx),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.edit_note,
                    color: AppColors.textSecondary(ctx),
                    size: 22,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    title,
                    style: TextStyle(
                      color: AppColors.textPrimary(ctx),
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    icon: const Icon(Icons.close, size: 16),
                    label: const Text('Cancel'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.textTertiary(ctx),
                    ),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.check, size: 16),
                    label: const Text('Apply'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.formMasterAccent,
                      foregroundColor: AppColors.onChaosAccent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                    ),
                    onPressed: () {
                      controller.text = expandedController.text;
                      Navigator.pop(ctx);
                    },
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: AppColors.borderOf(ctx)),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: AppTextField(
                  controller: expandedController,
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  style: TextStyle(
                    color: AppColors.textPrimary(ctx),
                    fontSize: 14,
                    height: 1.6,
                  ),
                  decoration: InputDecoration(
                    hoverColor: Colors.transparent,
                    hintText: hintText.isNotEmpty ? hintText : null,
                    hintStyle: TextStyle(
                      color: AppColors.textSecondary(ctx),
                    ),
                    filled: true,
                    fillColor: AppColors.surfaceContainerOf(ctx),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: AppColors.formMasterAccent),
                    ),
                    contentPadding: const EdgeInsets.all(16),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  // Defer disposal to end of frame so the dialog's widget tree fully detaches
  // before the controller is invalidated.
  WidgetsBinding.instance.addPostFrameCallback((_) => expandedController.dispose());
}
