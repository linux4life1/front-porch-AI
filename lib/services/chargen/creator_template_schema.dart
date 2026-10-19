// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

/// The creator's form as a template holds it: one flat map with the same
/// keys on both surfaces and a default for every key. The desktop maps it
/// to and from `CreatorState`, the phone to and from `ChargenForm`. A key
/// one surface does not show is kept when the other saves (see
/// [mergeTemplateForms]); the template's name lives beside the form, never
/// in it.
library;

import 'package:front_porch_ai/services/chargen/archetype_presets.dart';
import 'package:front_porch_ai/services/chargen/interview_questions.dart';

/// The file format's version, written in every template file.
const int kTemplateFormVersion = 1;

const int kTemplateNameMax = 80;

const String kTemplateReplacesCaption =
    'A template with this name already exists. Saving replaces it.';

const String kTemplateTakenProblem = 'Another template already has this name.';

/// What a template file that cannot be read shows in place of its summary.
const String kTemplateUnreadable = "This file can't be read";

/// Which surface shows a field. The other one keeps it through its saves.
enum TemplateSurface { both, desktop, phone }

class TemplateField {
  const TemplateField(
    this.key,
    this.fallback, {
    this.surface = TemplateSurface.both,
    this.options,
  });

  final String key;

  /// The value when the form has none, or one of the wrong type, or one
  /// outside [options].
  final Object? fallback;

  final TemplateSurface surface;

  /// The only values a text field may take; null allows any text.
  final List<String>? options;

  bool get onPhone => surface != TemplateSurface.desktop;
}

/// Every key a template holds. Text is `''`, lists are lists of strings,
/// `interviewQuestions` is the Interview card's rows (null: the standard
/// set).
const List<TemplateField> kTemplateFields = [
  TemplateField('mode', 'automated', options: ['automated', 'guided', 'quick']),
  TemplateField('nsfw', false),
  TemplateField('age', ''),
  TemplateField('sex', ''),
  TemplateField(
    'greetingLength',
    'Medium (2-4 paragraphs)',
    options: [
      'Short (1-2 paragraphs)',
      'Medium (2-4 paragraphs)',
      'Long (4-6 paragraphs)',
    ],
  ),
  TemplateField('altGreetingCount', 2),
  TemplateField('greetingTones', <String>['Neutral']),
  TemplateField(
    'generationDetail',
    'Standard',
    options: ['Brief', 'Standard', 'Detailed', 'Comprehensive'],
  ),
  TemplateField('narrativePerspective', 'first', options: ['first', 'third']),
  TemplateField('narrativeTense', 'present', options: ['present', 'past']),
  TemplateField('includeDynamicMacros', false),
  TemplateField('interviewQuestions', null),
  // The Interview card's switch: true asks nothing, keeping the rows.
  TemplateField('skipInterview', false),
  TemplateField('generateLorebook', true),
  TemplateField('loreCategories', <String>[]),
  TemplateField(
    'loreDepth',
    'Standard',
    options: ['Light', 'Standard', 'Deep'],
  ),
  // Quick and Automated.
  TemplateField('quickConcept', ''),
  TemplateField('automatedConcept', ''),
  TemplateField('automatedKeywords', ''),
  TemplateField('quickScenario', ''),
  // Guided.
  TemplateField('guidedVision', ''),
  TemplateField('guidedBuild', ''),
  TemplateField('guidedHair', ''),
  TemplateField('guidedFeatures', ''),
  TemplateField('guidedRace', ''),
  TemplateField('guidedPersonality', ''),
  TemplateField('guidedSpeech', ''),
  TemplateField('guidedSecret', ''),
  TemplateField('guidedOrigin', ''),
  TemplateField('guidedSetting', ''),
  TemplateField('guidedTone', ''),
  TemplateField('guidedRelationship', ''),
  TemplateField('guidedScenario', ''),
  TemplateField('guidedNsfwBody', ''),
  TemplateField('guidedNsfwExperience', ''),
  TemplateField('guidedNsfwDominance', ''),
  TemplateField('guidedNsfwKinks', ''),
  TemplateField('guidedNsfwClothing', ''),
  TemplateField('guidedNsfwPersonality', ''),
  // Automated's pickers.
  TemplateField('race', ''),
  TemplateField('bodyType', ''),
  TemplateField('hairLength', ''),
  TemplateField('hairStyle', ''),
  TemplateField('skinTone', ''),
  TemplateField('absCore', ''),
  TemplateField('thighs', ''),
  TemplateField('hips', ''),
  TemplateField('shoulders', ''),
  TemplateField('waist', ''),
  TemplateField('chestSize', ''),
  TemplateField('buttSize', ''),
  TemplateField('experience', ''),
  TemplateField('dominance', ''),
  TemplateField('outfitVibe', ''),
  TemplateField('backstoryOrigin', ''),
  TemplateField('backstoryTone', ''),
  TemplateField('backstoryEra', ''),
  TemplateField('customRace', ''),
  TemplateField('customKinks', ''),
  TemplateField('backstoryNotes', ''),
  TemplateField('notableFeatures', <String>[]),
  TemplateField('kinks', <String>[]),
  TemplateField('relationships', <String>[]),
  TemplateField('customRelationship', ''),
  // The desktop's own.
  TemplateField('artStyle', 'Anime', surface: TemplateSurface.desktop),
  TemplateField('reasoningEnabled', false, surface: TemplateSurface.desktop),
  TemplateField('personaId', '', surface: TemplateSurface.desktop),
  TemplateField('archetype', '', surface: TemplateSurface.desktop),
  TemplateField('conceptWritten', false, surface: TemplateSurface.desktop),
  TemplateField('loreUrls', <String>[], surface: TemplateSurface.desktop),
  // The phone's own.
  TemplateField('quickKeywords', '', surface: TemplateSurface.phone),
  TemplateField('worldLore', '', surface: TemplateSurface.phone),
];

final Map<String, TemplateField> _fieldByKey = {
  for (final f in kTemplateFields) f.key: f,
};

/// A fresh copy of every field's default.
Map<String, Object?> templateDefaults() => {
  for (final f in kTemplateFields)
    f.key: switch (f.fallback) {
      final List<String> words => List<String>.of(words),
      final other => other,
    },
};

/// Typed reads of a template form. A value that is absent, of the wrong
/// type, or outside the field's options reads as the field's default.
extension TemplateFormRead on Map<String, Object?> {
  String text(String k) {
    final v = this[k];
    final options = _fieldByKey[k]?.options;
    if (v is String && (options == null || options.contains(v))) return v;
    return switch (_fieldByKey[k]?.fallback) {
      final String s => s,
      _ => '',
    };
  }

  bool flag(String k) {
    final v = this[k];
    if (v is bool) return v;
    return _fieldByKey[k]?.fallback == true;
  }

  /// A count from 0 to [max].
  int count(String k, {int max = 5}) {
    final v = this[k];
    if (v is num && v.isFinite && v == v.roundToDouble()) {
      final n = v.toInt();
      if (n >= 0 && n <= max) return n;
    }
    return switch (_fieldByKey[k]?.fallback) {
      final int n => n,
      _ => 0,
    };
  }

  /// A list of strings; anything in it that is not a string is left out.
  List<String> words(String k) {
    final v = this[k];
    if (v is List) {
      return [
        for (final w in v)
          if (w is String) w,
      ];
    }
    return switch (_fieldByKey[k]?.fallback) {
      final List<String> words => List<String>.of(words),
      _ => <String>[],
    };
  }

  /// The Interview card's rows; null is the standard set.
  List<InterviewQuestion>? interview() =>
      InterviewQuestion.listFromJson(this['interviewQuestions']);
}

/// [layers] laid over each other, later keys winning; a key only an
/// earlier layer has survives. Any `name` key (the character's) is dropped.
Map<String, Object?> mergeTemplateForms(List<Map<String, Object?>?> layers) {
  final merged = <String, Object?>{};
  for (final layer in layers) {
    if (layer != null) merged.addAll(layer);
  }
  return merged..remove('name');
}

const int _slugMax = 48;

final Set<String> _windowsDeviceNames = {
  'con',
  'prn',
  'aux',
  'nul',
  for (var i = 1; i <= 9; i++) ...['com$i', 'lpt$i'],
};

/// A template's file name (without `.json`): the trimmed, lowercased name's
/// runs of a-z and 0-9 joined by `-`, at most 48 characters. A name with
/// any character outside ASCII, or nothing left, takes an 8-hex FNV-1a-32
/// of the lowered name. Windows device names take `-template`. The phone's
/// copy of this rule reads the same vectors
/// (`test/fixtures/chargen/creator_template_vectors.json`).
String templateSlug(String name) {
  final lowered = name.trim().toLowerCase();
  var slug = RegExp('[a-z0-9]+').allMatches(lowered).map((m) => m[0]).join('-');
  if (slug.length > _slugMax) {
    slug = slug.substring(0, _slugMax).replaceFirst(RegExp(r'-+$'), '');
  }
  if (slug.isEmpty || lowered.codeUnits.any((u) => u > 0x7f)) {
    final hash = _fnv1a32(lowered);
    slug = slug.isEmpty ? hash : '$slug-$hash';
  }
  return _windowsDeviceNames.contains(slug) ? '$slug-template' : slug;
}

/// FNV-1a, 32 bits, over UTF-16 code units (what the phone's JavaScript
/// sees), as 8 hex digits.
String _fnv1a32(String s) {
  var hash = 0x811c9dc5;
  for (final unit in s.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}

final Map<String, String> _builtInNameBySlug = {
  for (final name in kArchetypePresets.keys) templateSlug(name): name,
};

/// The built-in template's name when [slug] is one's, otherwise null.
String? builtInTemplateName(String slug) => _builtInNameBySlug[slug];

/// Why [name] cannot be saved as a template, in plain words; null when it
/// can. A built-in's name is matched by slug, so spacing and case do not
/// get around it.
String? templateNameProblem(String name) {
  final n = name.trim();
  if (n.isEmpty) return 'Give the template a name.';
  if (n.length > kTemplateNameMax) {
    return 'Keep the name to $kTemplateNameMax characters or fewer.';
  }
  final builtIn = builtInTemplateName(templateSlug(n));
  if (builtIn != null) {
    return "$builtIn is a built-in template and can't be changed. Give yours "
        'another name.';
  }
  return null;
}
