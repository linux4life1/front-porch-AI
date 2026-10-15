// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/services/chargen/creator_template.dart';
import 'package:front_porch_ai/services/chargen/creator_template_schema.dart';

/// Where the creator's templates live in the library at [root].
String chargenTemplatesDir(String root) => p.join(root, 'chargen', 'templates');

/// Why the library did not do what it was asked, with the relay's status:
/// 400 a name problem, 404 no such template, 409 a built-in, a taken name
/// or a file that can only be deleted.
class TemplateRefused implements Exception {
  const TemplateRefused(this.status, this.message, {this.reason});

  final int status;
  final String message;

  /// On a 409: `builtIn`, `taken` or `broken`.
  final String? reason;

  @override
  String toString() => 'TemplateRefused($status): $message';
}

/// The refusal for saving under [name], or null when it can be saved.
TemplateRefused? templateNameRefusal(String name) {
  final problem = templateNameProblem(name);
  if (problem == null) return null;
  return builtInTemplateName(templateSlug(name)) != null
      ? TemplateRefused(409, problem, reason: 'builtIn')
      : TemplateRefused(400, problem);
}

const String _gone = 'This template is not there any more.';

/// The user's creator templates, one `<slug>.json` per template in [dir].
/// The desktop and the relay use this class on the one folder. Reads never
/// throw: a file that cannot be read is listed as broken. Writes go one at
/// a time per folder, each to a temporary file renamed into place.
class ChargenTemplateLibrary {
  const ChargenTemplateLibrary(this.dir);

  final String dir;

  /// The library in the library folder [root]; null when there is none.
  static ChargenTemplateLibrary? under(String? root) =>
      root == null || root.isEmpty
      ? null
      : ChargenTemplateLibrary(chargenTemplatesDir(root));

  /// The last write in line, per folder.
  static final Map<String, Future<void>> _writes = {};

  /// Yours, newest first, broken files included. A file named like a
  /// built-in is left out (and logged): the built-in owns that name.
  Future<List<CreatorTemplate>> listMine() async {
    final List<FileSystemEntity> entries;
    try {
      final folder = Directory(dir);
      if (!await folder.exists()) return [];
      entries = await folder.list(followLinks: false).toList();
    } on FileSystemException catch (e) {
      debugPrint('[Templates] cannot list $dir: $e');
      return [];
    }
    final mine = <CreatorTemplate>[];
    for (final entry in entries) {
      final base = p.basename(entry.path);
      if (!base.endsWith('.json') || base.length == '.json'.length) continue;
      final slug = base.substring(0, base.length - '.json'.length);
      if (builtInTemplate(slug) != null) {
        debugPrint(
          '[Templates] ${entry.path} is named like a built-in; skipped',
        );
        continue;
      }
      mine.add(await _open(entry.path, slug));
    }
    return mine..sort(_newestFirst);
  }

  /// Yours, then the built-ins.
  Future<List<CreatorTemplate>> list() async => [
    ...await listMine(),
    ...kBuiltInTemplates,
  ];

  /// Your template [slug]; null when there is none.
  Future<CreatorTemplate?> read(String slug) async {
    final path = _pathOf(slug);
    if (path == null || builtInTemplate(slug) != null) return null;
    if (!await _exists(path)) return null;
    return _open(path, slug);
  }

  /// Saves [form] as the template [name], over any of that name. The file
  /// keeps keys the form does not carry: the stored template's, then those
  /// of the one it was started from ([basedOn], a built-in or yours), then
  /// [form]'s on top. Throws [TemplateRefused] for a name it cannot take.
  Future<({CreatorTemplate template, bool replaced})> save(
    String name,
    Map<String, Object?> form, {
    String? basedOn,
    DateTime? now,
  }) async {
    final refused = templateNameRefusal(name);
    if (refused != null) throw refused;
    final slug = templateSlug(name);
    return _inLine(() async {
      final stored = await read(slug);
      final base = basedOn == null || basedOn == slug
          ? null
          : builtInTemplate(basedOn) ?? await read(basedOn);
      final template = CreatorTemplate(
        slug: slug,
        name: name.trim(),
        savedAt: (now ?? DateTime.now()).toUtc(),
        form: mergeTemplateForms([
          if (stored != null && !stored.broken) stored.form,
          if (base != null && !base.broken) base.form,
          form,
        ]),
      );
      await _write(template);
      return (template: template, replaced: stored != null);
    });
  }

  /// Gives template [slug] the name [name], moving its file. Throws
  /// [TemplateRefused]: a built-in (either side), a taken name, a file that
  /// cannot be read, or none there.
  Future<CreatorTemplate> rename(String slug, String name) async {
    final builtIn = builtInTemplateName(slug);
    if (builtIn != null) {
      throw TemplateRefused(
        409,
        "$builtIn is a built-in template and can't be changed.",
        reason: 'builtIn',
      );
    }
    final refused = templateNameRefusal(name);
    if (refused != null) throw refused;
    final to = templateSlug(name);
    return _inLine(() async {
      final stored = await read(slug);
      if (stored == null) throw const TemplateRefused(404, _gone);
      if (stored.broken) {
        throw const TemplateRefused(
          409,
          "$kTemplateUnreadable, so it can only be deleted.",
          reason: 'broken',
        );
      }
      if (to != slug && await _exists(p.join(dir, '$to.json'))) {
        throw const TemplateRefused(
          409,
          kTemplateTakenProblem,
          reason: 'taken',
        );
      }
      final renamed = stored.renamed(to, name.trim());
      await _write(renamed);
      if (to != slug) await File(p.join(dir, '$slug.json')).delete();
      return renamed;
    });
  }

  /// Deletes template [slug]. Throws [TemplateRefused] for a built-in or
  /// one that is not there. A folder in the file's place is removed only
  /// when it is empty.
  Future<void> delete(String slug) async {
    final builtIn = builtInTemplateName(slug);
    if (builtIn != null) {
      throw TemplateRefused(
        409,
        "$builtIn is a built-in template and can't be deleted.",
        reason: 'builtIn',
      );
    }
    final path = _pathOf(slug);
    if (path == null) throw const TemplateRefused(404, _gone);
    return _inLine(() async {
      final type = await FileSystemEntity.type(path, followLinks: false);
      if (type == FileSystemEntityType.notFound) {
        throw const TemplateRefused(404, _gone);
      }
      if (type == FileSystemEntityType.directory) {
        await Directory(path).delete();
      } else {
        await File(path).delete();
      }
    });
  }

  /// Where template [slug] is kept; null for a slug that is not a plain
  /// file name (a path from the relay is never followed out of [dir]).
  String? _pathOf(String slug) {
    if (slug.isEmpty ||
        slug.startsWith('.') ||
        RegExp(r'[\\/:*?"<>|\x00-\x1F]').hasMatch(slug)) {
      return null;
    }
    return p.join(dir, '$slug.json');
  }

  static Future<bool> _exists(String path) async =>
      await FileSystemEntity.type(path, followLinks: false) !=
      FileSystemEntityType.notFound;

  static Future<CreatorTemplate> _open(String path, String slug) async {
    try {
      return CreatorTemplate.fromFile(slug, await File(path).readAsString());
    } on FileSystemException catch (e) {
      return CreatorTemplate.unreadable(slug, e.message);
    } on FormatException catch (e) {
      return CreatorTemplate.unreadable(slug, e.message);
    }
  }

  static int _newestFirst(CreatorTemplate a, CreatorTemplate b) {
    final at = a.savedAt;
    final bt = b.savedAt;
    if (at != null && bt != null && at != bt) return bt.compareTo(at);
    if (at == null && bt != null) return 1;
    if (at != null && bt == null) return -1;
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  }

  /// Runs [write] once every earlier write to this folder has finished. A
  /// failed write still fails its own caller; the line moves on.
  Future<T> _inLine<T>(Future<T> Function() write) {
    final key = p.canonicalize(dir);
    final run = (_writes[key] ?? Future<void>.value()).then((_) => write());
    _writes[key] = run.then<void>((_) {}, onError: (Object _) {});
    return run;
  }

  Future<void> _write(CreatorTemplate t) async {
    await Directory(dir).create(recursive: true);
    final target = File(p.join(dir, '${t.slug}.json'));
    final temp = File('${target.path}.tmp');
    await temp.writeAsString(
      const JsonEncoder.withIndent('  ').convert(t.toFile()),
      flush: true,
    );
    try {
      await temp.rename(target.path);
    } on FileSystemException {
      // Windows will not rename over a file another process has open.
      try {
        if (await target.exists()) await target.delete();
        await temp.rename(target.path);
      } on FileSystemException catch (e) {
        debugPrint('[Templates] could not write ${target.path}: $e');
        if (await temp.exists()) await temp.delete();
        rethrow;
      }
    }
  }
}
