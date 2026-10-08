// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'image_prompt.dart';

class ExpressionPromptReplacement {
  ExpressionPromptReplacement({
    required this.find,
    required this.replace,
    this.caseSensitive = true,
  }) {
    if (find.isEmpty) throw const FormatException('Find text cannot be empty.');
    if (find.length > 2048 || replace.length > 2048) {
      throw const FormatException(
        'Replacement text must be at most 2048 characters.',
      );
    }
  }
  final String find;
  final String replace;
  final bool caseSensitive;
  Map<String, Object> toJson() => {
    'find': find,
    'replace': replace,
    'caseSensitive': caseSensitive,
  };
  static ExpressionPromptReplacement fromJson(Object? value) {
    if (value is! Map ||
        value['find'] is! String ||
        value['replace'] is! String ||
        (value.containsKey('caseSensitive') &&
            value['caseSensitive'] is! bool)) {
      throw const FormatException(
        'Each replacement needs literal find and replace text.',
      );
    }
    return ExpressionPromptReplacement(
      find: value['find'] as String,
      replace: value['replace'] as String,
      caseSensitive: value['caseSensitive'] as bool? ?? true,
    );
  }
}

class ExpressionPromptRules {
  ExpressionPromptRules({
    this.prefix = '',
    this.suffix = '',
    List<ExpressionPromptReplacement> replacements = const [],
  }) : replacements = List.unmodifiable(replacements) {
    if (prefix.length > 4096 ||
        suffix.length > 4096 ||
        replacements.length > 32) {
      throw const FormatException(
        'Use at most 32 replacements and 4096 characters per prefix or suffix.',
      );
    }
  }
  final String prefix;
  final String suffix;
  final List<ExpressionPromptReplacement> replacements;
  ExpressionPromptRules copy() => ExpressionPromptRules(
    prefix: prefix,
    suffix: suffix,
    replacements: replacements,
  );
  Map<String, Object> toJson() => {
    'prefix': prefix,
    'suffix': suffix,
    'replacements': [for (final r in replacements) r.toJson()],
  };
  static ExpressionPromptRules fromJson(Object? value) {
    if (value is! Map ||
        (value.containsKey('prefix') && value['prefix'] is! String) ||
        (value.containsKey('suffix') && value['suffix'] is! String) ||
        (value.containsKey('replacements') && value['replacements'] is! List)) {
      throw const FormatException(
        'Prompt rules need prefix, suffix, and a replacements list.',
      );
    }
    final rows = value['replacements'] as List? ?? const [];
    if (rows.length > 32) {
      throw const FormatException('Use at most 32 replacements.');
    }
    return ExpressionPromptRules(
      prefix: value['prefix'] as String? ?? '',
      suffix: value['suffix'] as String? ?? '',
      replacements: [
        for (final r in rows) ExpressionPromptReplacement.fromJson(r),
      ],
    );
  }

  static const maxPromptLength = 16384;
  static void _checkLength(int length) {
    if (length > maxPromptLength) {
      throw const FormatException(
        'The effective prompt must be at most 16384 characters.',
      );
    }
  }

  String apply(String original) {
    if (prefix.isEmpty && suffix.isEmpty && replacements.isEmpty) {
      return original;
    }
    _checkLength(original.length);
    var prompt = original;
    for (final r in replacements) {
      final pattern = RegExp(
        RegExp.escape(r.find),
        caseSensitive: r.caseSensitive,
      );
      var length = prompt.length;
      for (final _ in pattern.allMatches(prompt)) {
        length += r.replace.length - r.find.length;
        _checkLength(length);
      }
      prompt = prompt.replaceAllMapped(pattern, (_) => r.replace);
    }
    _checkLength(
      prompt.length +
          prefix.length +
          suffix.length +
          (prefix.isEmpty ? 0 : 1) +
          (suffix.isEmpty ? 0 : 1),
    );
    return [
      if (prefix.isNotEmpty) prefix,
      prompt,
      if (suffix.isNotEmpty) suffix,
    ].join(' ');
  }
}

String originalExpressionPrompt({
  required String emotion,
  required String basePrompt,
  required bool editMode,
}) => editMode
    ? expressionEditInstruction(emotion)
    : '${kExpressionModifiers[emotion] ?? emotion}, $basePrompt';

String composeExpressionPrompt({
  required String emotion,
  required String basePrompt,
  required bool editMode,
  required ExpressionPromptRules rules,
}) => rules.apply(
  originalExpressionPrompt(
    emotion: emotion,
    basePrompt: basePrompt,
    editMode: editMode,
  ),
);
