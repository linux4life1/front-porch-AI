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

// Parse Comfy's /templates/index.json. Studio only lists Create / Edit
// templates — no ControlNet, inpaint, or paid API graphs.

class ComfyTemplateEntry {
  final String name;
  final String title;
  final List<String> tags;
  final bool openSource;
  final String source; // default | userdata | bundled

  const ComfyTemplateEntry({
    required this.name,
    required this.title,
    this.tags = const [],
    this.openSource = true,
    this.source = 'default',
  });

  String get pickerId => 'comfy:$name';

  bool get isCreate =>
      _has(_kCreateTags) && !_has(_kBlockedTags) && openSource;

  bool get isEdit => _has(_kEditTags) && !_has(_kBlockedTags) && openSource;

  bool _has(Set<String> needles) {
    for (final t in tags) {
      final s = t.toLowerCase();
      for (final n in needles) {
        if (s.contains(n)) return true;
      }
    }
    final titleLc = title.toLowerCase();
    for (final n in needles) {
      if (titleLc.contains(n)) return true;
    }
    return false;
  }
}

const _kCreateTags = {'text to image', 'text-to-image', 't2i'};
const _kEditTags = {'image edit', 'image-edit', 'instruct'};
const _kBlockedTags = {
  'controlnet',
  'inpaint',
  'outpaint',
  'canny',
  'depth',
  'redux',
  'fill',
  'api',
};

/// Comfy serves a list of category objects, each with a `templates` array.
List<ComfyTemplateEntry> parseComfyTemplateIndex(Object? raw) {
  final out = <ComfyTemplateEntry>[];
  if (raw is! List) return out;
  for (final cat in raw) {
    if (cat is! Map) continue;
    final templates = cat['templates'];
    if (templates is! List) continue;
    for (final t in templates) {
      if (t is! Map) continue;
      final name = t['name']?.toString() ?? '';
      if (name.isEmpty) continue;
      final tags = <String>[];
      final rawTags = t['tags'];
      if (rawTags is List) {
        tags.addAll(rawTags.map((e) => e.toString()));
      }
      out.add(
        ComfyTemplateEntry(
          name: name,
          title: t['title']?.toString().trim().isNotEmpty == true
              ? t['title'].toString()
              : name,
          tags: tags,
          openSource: t['openSource'] != false,
        ),
      );
    }
  }
  return out;
}

List<ComfyTemplateEntry> comfyCreateTemplates(List<ComfyTemplateEntry> all) =>
    all.where((e) => e.isCreate).toList();

List<ComfyTemplateEntry> comfyEditTemplates(List<ComfyTemplateEntry> all) =>
    all.where((e) => e.isEdit).toList();
