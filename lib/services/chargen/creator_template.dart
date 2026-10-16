// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;

import 'package:front_porch_ai/services/chargen/archetype_presets.dart';
import 'package:front_porch_ai/services/chargen/creator_template_schema.dart';

/// One template: a file in the library, or a built-in archetype.
class CreatorTemplate {
  const CreatorTemplate({
    required this.slug,
    required this.name,
    this.savedAt,
    this.builtIn = false,
    this.form = const {},
    this.problem,
  });

  final String slug;
  final String name;

  /// When the form was last saved, in UTC; null for a built-in or a file
  /// that cannot be read.
  final DateTime? savedAt;

  final bool builtIn;
  final Map<String, Object?> form;

  /// Set when the file cannot be read; such a template can only be deleted.
  final String? problem;

  bool get broken => problem != null;

  TemplateSummary get summary => TemplateSummary(
    mode: form.text('mode'),
    perspective: form.text('narrativePerspective'),
    tense: form.text('narrativeTense'),
    lore: form.flag('generateLorebook'),
    nsfw: form.flag('nsfw'),
    blurb: builtIn ? _keywordsOf(name).join(', ') : null,
  );

  /// The same form under another name.
  CreatorTemplate renamed(String slug, String name) =>
      CreatorTemplate(slug: slug, name: name, savedAt: savedAt, form: form);

  /// As the relay sends it.
  Map<String, Object?> toJson() => {
    'slug': slug,
    'name': name,
    'savedAt': savedAt?.toUtc().toIso8601String(),
    'builtIn': builtIn,
    if (broken) 'broken': true,
    if (broken) 'problem': problem,
    'summary': summary.toJson(),
    'form': form,
  };

  /// As the library writes it.
  Map<String, Object?> toFile() => {
    'version': kTemplateFormVersion,
    'name': name,
    'savedAt': savedAt?.toUtc().toIso8601String(),
    'form': form,
  };

  /// The template in the file `<slug>.json`, given its text or its decoded
  /// JSON. Never throws: text that is not JSON, JSON that is not an object,
  /// or an object with no name comes back [broken].
  static CreatorTemplate fromFile(String slug, Object? json) {
    var data = json;
    if (data is String) {
      try {
        data = jsonDecode(data);
      } on FormatException catch (e) {
        return unreadable(slug, 'not JSON (${e.message})');
      }
    }
    if (data is! Map) return unreadable(slug, 'not a JSON object');
    final name = data['name'];
    if (name is! String || name.trim().isEmpty) {
      return unreadable(slug, 'it has no name');
    }
    final form = data['form'] ?? const <String, Object?>{};
    if (form is! Map) return unreadable(slug, 'its form is not an object');
    final savedAt = data['savedAt'];
    return CreatorTemplate(
      slug: slug,
      name: name.trim(),
      savedAt: savedAt is String ? DateTime.tryParse(savedAt)?.toUtc() : null,
      form: mergeTemplateForms([
        {for (final e in form.entries) '${e.key}': e.value},
      ]),
    );
  }

  /// The file `<slug>.json` that cannot be read as a template; [why] is
  /// logged, the screen says [kTemplateUnreadable].
  static CreatorTemplate unreadable(String slug, String why) {
    debugPrint('[Templates] $slug.json cannot be read: $why');
    return CreatorTemplate(
      slug: slug,
      name: slug,
      problem: kTemplateUnreadable,
    );
  }
}

/// What a template's tile says about it.
class TemplateSummary {
  const TemplateSummary({
    required this.mode,
    required this.perspective,
    required this.tense,
    required this.lore,
    required this.nsfw,
    this.blurb,
  });

  final String mode;
  final String perspective;
  final String tense;
  final bool lore;
  final bool nsfw;

  /// A built-in's keywords, its own name left out; null for the user's.
  final String? blurb;

  Map<String, Object?> toJson() => {
    'mode': mode,
    'perspective': perspective,
    'tense': tense,
    'lore': lore,
    'nsfw': nsfw,
    'blurb': blurb,
  };
}

/// An archetype's keywords without its own name.
List<String> _keywordsOf(String archetype) => [
  for (final raw in (kArchetypePresets[archetype]?['keywords'] ?? '').split(
    ',',
  ))
    if (raw.trim().isNotEmpty &&
        raw.trim().toLowerCase() != archetype.toLowerCase())
      raw.trim(),
];

const List<String> _featured = ['Tsundere', 'Kuudere'];

CreatorTemplate _builtIn(String name, Map<String, String> preset) {
  final form = {
    ...templateDefaults(),
    'mode': 'automated',
    'archetype': name,
    'automatedConcept': preset['concept'] ?? '',
    'automatedKeywords': preset['keywords'] ?? '',
  };
  return CreatorTemplate(
    slug: templateSlug(name),
    name: name,
    builtIn: true,
    form: Map.unmodifiable({
      for (final MapEntry(:key, :value) in form.entries)
        key: value is List<String> ? List<String>.unmodifiable(value) : value,
    }),
  );
}

final List<CreatorTemplate> _builtIns = List.unmodifiable([
  for (final MapEntry(:key, :value) in kArchetypePresets.entries)
    if (_featured.contains(key)) _builtIn(key, value),
  for (final MapEntry(:key, :value) in kArchetypePresets.entries)
    if (!_featured.contains(key)) _builtIn(key, value),
]);

/// The fifteen archetypes as read-only templates: Tsundere and Kuudere
/// first, then the rest in the creator's order.
List<CreatorTemplate> get kBuiltInTemplates => _builtIns;

/// The Mode step's last tile.
String get kAllBuiltInLabel => 'All ${kBuiltInTemplates.length} built in';

CreatorTemplate? builtInTemplate(String slug) {
  for (final t in _builtIns) {
    if (t.slug == slug) return t;
  }
  return null;
}

/// A tile's second line. Yours: `{Mode} · {1st|3rd} person, {tense} · lore
/// on · 18+`, the parts that apply; the phone leaves out the voice. A
/// built-in: `Automated · ` and its first two keywords (the phone, one).
String templateSummaryLine(CreatorTemplate t, {bool phone = false}) {
  if (t.broken) return kTemplateUnreadable;
  final s = t.summary;
  final mode = s.mode.isEmpty
      ? s.mode
      : '${s.mode[0].toUpperCase()}${s.mode.substring(1)}';
  if (t.builtIn) {
    return '$mode · ${_keywordsOf(t.name).take(phone ? 1 : 2).join(', ')}';
  }
  return [
    mode,
    if (!phone)
      '${s.perspective == 'third' ? '3rd' : '1st'} person, ${s.tense}',
    if (s.lore) 'lore on',
    if (s.nsfw) '18+',
  ].join(' · ');
}

const List<String> _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// `Saved 4 Oct`, with the year when it is not [now]'s. Both are read in
/// local time.
String templateSavedLabel(DateTime savedAtUtc, {required DateTime now}) {
  final at = savedAtUtc.toLocal();
  final day = '${at.day} ${_months[at.month - 1]}';
  return at.year == now.toLocal().year ? 'Saved $day' : 'Saved $day ${at.year}';
}
