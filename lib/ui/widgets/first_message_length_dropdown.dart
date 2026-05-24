import 'package:flutter/material.dart';

import 'styled_dropdown.dart';

class FirstMessageLengthDropdown extends StatelessWidget {
  const FirstMessageLengthDropdown({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final String value;
  final ValueChanged<String?> onChanged;

  static const _greetingLengths = [
    'Short (1-2 paragraphs)',
    'Medium (2-4 paragraphs)',
    'Long (4-6 paragraphs)',
  ];

  @override
  Widget build(BuildContext context) {
    return StyledDropdown<String>(
      value: value,
      items: _greetingLengths
          .map((len) => DropdownMenuItem(value: len, child: Text(len)))
          .toList(),
      onChanged: onChanged,
    );
  }
}
