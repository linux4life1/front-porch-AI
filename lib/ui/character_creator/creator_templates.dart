// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/services/chargen/chargen.dart';
import 'package:front_porch_ai/ui/character_creator/creator_state.dart';
import 'package:front_porch_ai/ui/character_creator/creator_state/creator_template_form.dart';

/// The template a form was loaded from: what the Configure step's
/// `Started from` pill names. Saved with the creator's preferences.
@immutable
class TemplateStart {
  const TemplateStart({
    required this.slug,
    required this.name,
    this.builtIn = false,
  });

  final String slug;
  final String name;
  final bool builtIn;

  Map<String, Object?> toJson() => {
    'slug': slug,
    'name': name,
    'builtIn': builtIn,
  };

  /// What [toJson] wrote; null for anything else.
  static TemplateStart? fromJson(Object? json) {
    if (json is! Map) return null;
    final slug = json['slug'];
    final name = json['name'];
    if (slug is! String || slug.isEmpty || name is! String) return null;
    return TemplateStart(
      slug: slug,
      name: name,
      builtIn: json['builtIn'] == true,
    );
  }

  /// The preference value: `''` for no mark.
  static String toPrefs(TemplateStart? start) =>
      start == null ? '' : jsonEncode(start.toJson());

  /// Reads what [toPrefs] wrote; unreadable text is logged and gives none.
  static TemplateStart? fromPrefs(String raw) {
    if (raw.trim().isEmpty) return null;
    try {
      final start = fromJson(jsonDecode(raw));
      if (start == null) throw const FormatException('not a template mark');
      return start;
    } on FormatException catch (e) {
      debugPrint('CharacterCreator: saved template mark unreadable: $e');
      return null;
    }
  }
}

/// The creator's templates (docs/design/creator-templates.md): the user's
/// list for the Mode step, loading one into the form, saving the form as
/// one, and the `Started from` mark. Held by `CreatorState`; every change
/// to the list or the mark is followed by [_changed], and every change to
/// the mark by [_save], so a restart keeps it.
class CreatorTemplates {
  CreatorTemplates(this._changed, {Future<void> Function()? save})
    : _save = save;

  final VoidCallback _changed;
  final Future<void> Function()? _save;

  /// The library folder's templates; null (no I/O, built-ins only) until
  /// the creator page sets it.
  ChargenTemplateLibrary? library;

  /// Yours, newest first, files that cannot be read included.
  List<CreatorTemplate> mine = const [];

  TemplateStart? startedFrom;

  /// Each list read takes a ticket; one a newer read or a save, rename or
  /// delete overtook is dropped, so an older list never lands last.
  int _ticket = 0;

  /// Re-reads [mine]. Without a library there is nothing to read and
  /// nothing notifies, so a first build can call it. A mark left by a
  /// template that is gone (deleted on the phone) is dropped.
  Future<void> refresh() async {
    final lib = library;
    if (lib == null) return;
    final ticket = ++_ticket;
    final list = await lib.listMine();
    if (ticket != _ticket) return;
    mine = list;
    final start = startedFrom;
    if (start != null &&
        !start.builtIn &&
        !list.any((t) => t.slug == start.slug)) {
      _mark(null);
      return;
    }
    _changed();
  }

  /// Fills [s] from [t] and marks it `Started from`. A built-in fills the
  /// whole form from the defaults plus its archetype and, like every
  /// template, leaves the name alone. A persona [personaIds] does not hold
  /// is dropped: the persona picker has no row for it.
  void load(
    CreatorState s,
    CreatorTemplate t, {
    Iterable<String> personaIds = const [],
  }) {
    if (t.broken) return;
    final mode = applyCreatorTemplateForm(s, t.form);
    if (s.selectedPersonaId.isNotEmpty &&
        !personaIds.contains(s.selectedPersonaId)) {
      s.selectedPersonaId = '';
    }
    startedFrom = TemplateStart(slug: t.slug, name: t.name, builtIn: t.builtIn);
    s.creatorMode = mode;
    _save?.call();
    _changed();
  }

  /// Whether [name] can be saved: its problem, or that it would replace one
  /// of yours. Renaming [renaming], a name another template has is taken.
  ({String? problem, bool replaces}) checkName(
    String name, {
    CreatorTemplate? renaming,
  }) {
    final problem = templateNameProblem(name);
    if (problem != null) return (problem: problem, replaces: false);
    final slug = templateSlug(name);
    final owner = mine.where((t) => t.slug == slug).firstOrNull;
    if (owner == null) return (problem: null, replaces: false);
    if (renaming != null) {
      return owner.slug == renaming.slug
          ? (problem: null, replaces: false)
          : (problem: kTemplateTakenProblem, replaces: false);
    }
    return (problem: null, replaces: true);
  }

  /// Saves [s]'s form as the template [name], over one of that name, and
  /// marks the form as started from it. Keys the desktop does not show
  /// (the phone's own) are kept from the file it replaces and the template
  /// the form was started from. Throws [TemplateRefused] for a name the
  /// library will not take.
  Future<CreatorTemplate> saveAs(CreatorState s, String name) async {
    final lib = _need();
    final saved = await lib.save(
      name,
      creatorTemplateForm(s),
      basedOn: startedFrom?.slug,
    );
    final t = saved.template;
    _ticket++;
    mine = [t, ...mine.where((m) => m.slug != t.slug)];
    _mark(TemplateStart(slug: t.slug, name: t.name));
    return t;
  }

  /// Renames [t]; a form started from it follows the new name.
  Future<void> rename(CreatorTemplate t, String name) async {
    final renamed = await _need().rename(t.slug, name);
    _ticket++;
    mine = [
      for (final m in mine)
        if (m.slug == t.slug) renamed else m,
    ];
    if (_startedFromMine(t)) {
      _mark(TemplateStart(slug: renamed.slug, name: renamed.name));
    } else {
      _changed();
    }
  }

  /// Deletes [t]; a form started from it loses the mark and keeps its boxes.
  Future<void> delete(CreatorTemplate t) async {
    await _need().delete(t.slug);
    _ticket++;
    mine = [
      for (final m in mine)
        if (m.slug != t.slug) m,
    ];
    if (_startedFromMine(t)) {
      _mark(null);
    } else {
      _changed();
    }
  }

  /// Drops the mark (Clear Everything). The caller notifies and saves.
  void clearStartedFrom() => startedFrom = null;

  bool _startedFromMine(CreatorTemplate t) {
    final start = startedFrom;
    return start != null && !start.builtIn && start.slug == t.slug;
  }

  void _mark(TemplateStart? start) {
    startedFrom = start;
    _save?.call();
    _changed();
  }

  ChargenTemplateLibrary _need() {
    final lib = library;
    if (lib == null) {
      throw StateError('The templates folder is not known yet.');
    }
    return lib;
  }
}
