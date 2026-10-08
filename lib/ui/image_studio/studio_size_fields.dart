// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:front_porch_ai/services/image/image.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Width and height. Leaving a field snaps it to a multiple of 64.
class StudioSizeFields extends StatefulWidget {
  const StudioSizeFields({
    super.key,
    this.width = 1024,
    this.height = 1024,
    this.onChanged,
  });

  final int width;
  final int height;
  final void Function(int width, int height)? onChanged;

  @override
  State<StudioSizeFields> createState() => _StudioSizeFieldsState();
}

class _StudioSizeFieldsState extends State<StudioSizeFields> {
  late final TextEditingController _width = TextEditingController(
    text: '${widget.width}',
  );
  late final TextEditingController _height = TextEditingController(
    text: '${widget.height}',
  );

  @override
  void dispose() {
    _width.dispose();
    _height.dispose();
    super.dispose();
  }

  void _commit() {
    final snapped = snapStudioSize(
      int.tryParse(_width.text.trim()) ?? widget.width,
      int.tryParse(_height.text.trim()) ?? widget.height,
    );
    _width.text = '${snapped.width}';
    _height.text = '${snapped.height}';
    widget.onChanged?.call(snapped.width, snapped.height);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _field(context, 'Width', _width, const Key('studio-width')),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _field(context, 'Height', _height, const Key('studio-height')),
        ),
      ],
    );
  }

  Widget _field(
    BuildContext context,
    String label,
    TextEditingController controller,
    Key fieldKey,
  ) {
    return TextField(
      key: fieldKey,
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      onEditingComplete: _commit,
      onSubmitted: (_) => _commit(),
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        labelStyle: TextStyle(color: AppColors.textSecondary(context)),
      ),
      style: TextStyle(color: AppColors.textPrimary(context)),
    );
  }
}
