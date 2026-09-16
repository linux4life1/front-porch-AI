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

import 'package:front_porch_ai/services/chat/mediawiki_search.dart';
import 'package:front_porch_ai/services/chat/prompt_injection/prompt_injection.dart';

/// Neokosmos is ~4.1MB. 2MB would drop the notebook; 8MB holds it.
const int kTiddlyMaxBodyBytes = 8 * 1024 * 1024;
const int kTiddlySearchMaxHits = 5;
const int kTiddlySearchClipChars = 280;
const int kTiddlyTextHeadChars = 400;

final _storeScriptRe = RegExp(
  r'<script\b([^>]*)>(.*?)</script>',
  caseSensitive: false,
  dotAll: true,
);
final _transcludeRe = RegExp(r'\{\{[^}]*\}\}');
final _junkExt = [
  '.png',
  '.jpg',
  '.jpeg',
  '.gif',
  '.svg',
  '.webp',
  '.ico',
  '.bmp',
  '.mp3',
  '.mp4',
  '.webm',
  '.ogg',
  '.wav',
  '.m4a',
  '.aac',
];

/// One searchable tiddler. [text] is already plain (no HTML dump).
class TiddlyTiddler {
  const TiddlyTiddler({required this.title, required this.text});

  final String title;
  final String text;

  String get textHead {
    if (text.length <= kTiddlyTextHeadChars) return text;
    return text.substring(0, kTiddlyTextHeadChars);
  }
}

/// Session-cached notebook. Junk / `$:/` tiddlers are not stored.
class TiddlyIndex {
  const TiddlyIndex({
    required this.tiddlers,
    required this.skippedSystem,
    required this.parsedCount,
  });

  final List<TiddlyTiddler> tiddlers;
  final int skippedSystem;
  final int parsedCount;
}

bool looksLikeTiddlyStoreHtml(String html) {
  final lower = html.toLowerCase();
  return lower.contains('tiddlywiki-tiddler-store') ||
      (lower.contains('application/json') &&
          html.contains('"title"') &&
          html.contains('"text"'));
}

Uri tiddlyFetchUri(Uri base) {
  var path = base.path.isEmpty ? '/' : base.path;
  final segs = [
    for (final p in path.split('/'))
      if (p.isNotEmpty) p,
  ];
  final looksFile = segs.isNotEmpty && segs.last.contains('.');
  if (!looksFile && !path.endsWith('/')) path = '$path/';
  return Uri(
    scheme: base.scheme,
    host: base.host,
    port: base.hasPort ? base.port : null,
    path: path,
  );
}

/// Parse TW5 `tiddlywiki-tiddler-store` JSON (and JSON tiddler arrays).
/// Null when the HTML has no store.
TiddlyIndex? parseTiddlyStoreHtml(String html) {
  if (html.trim().isEmpty) return null;
  final kept = <TiddlyTiddler>[];
  final seen = <String>{};
  var skippedSystem = 0;
  var parsedCount = 0;
  var foundStore = false;

  for (final m in _storeScriptRe.allMatches(html)) {
    final attrs = m.group(1) ?? '';
    var body = (m.group(2) ?? '').trim();
    if (!_isTiddlerStoreScript(attrs, body)) continue;
    if (body.startsWith('<!--')) {
      body = body
          .replaceFirst(RegExp(r'^<!--'), '')
          .replaceFirst(RegExp(r'-->$'), '')
          .trim();
    }
    final dynamic json;
    try {
      json = jsonDecode(body);
    } catch (_) {
      continue;
    }
    if (json is! List) continue;
    foundStore = true;
    for (final raw in json) {
      if (raw is! Map) continue;
      parsedCount++;
      final title = (raw['title']?.toString() ?? '').trim();
      if (title.startsWith('\$:/')) {
        skippedSystem++;
        continue;
      }
      final type = raw['type']?.toString() ?? '';
      if (_isJunkTiddler(title: title, type: type)) continue;
      final text = _plainTiddlerText(raw['text']?.toString() ?? '', type);
      if (title.isEmpty) continue;
      if (!seen.add(title.toLowerCase())) continue;
      kept.add(TiddlyTiddler(title: title, text: text));
    }
  }
  if (!foundStore) return null;
  return TiddlyIndex(
    tiddlers: kept,
    skippedSystem: skippedSystem,
    parsedCount: parsedCount,
  );
}

List<TiddlyTiddler> searchTiddlyIndex(
  TiddlyIndex index,
  String query, {
  int maxHits = kTiddlySearchMaxHits,
}) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return const [];
  final scored = <(int, TiddlyTiddler)>[];
  for (final t in index.tiddlers) {
    final title = t.title.toLowerCase();
    final head = t.textHead.toLowerCase();
    var score = 0;
    if (title == q) {
      score = 100;
    } else if (title.startsWith(q)) {
      score = 80;
    } else if (title.contains(q)) {
      score = 60;
    }
    if (head.contains(q)) score += 20;
    if (score > 0) scored.add((score, t));
  }
  scored.sort((a, b) {
    final c = b.$1.compareTo(a.$1);
    if (c != 0) return c;
    return a.$2.title.compareTo(b.$2.title);
  });
  return [for (final s in scored.take(maxHits)) s.$2];
}

String formatTiddlySearchHits(List<TiddlyTiddler> hits) {
  final buf = StringBuffer();
  for (final t in hits) {
    if (buf.isNotEmpty) buf.writeln();
    buf.write(t.title);
    var clip = t.text;
    if (clip.length > kTiddlySearchClipChars) {
      clip = clip.substring(0, kTiddlySearchClipChars).trim();
    }
    if (clip.isNotEmpty) buf.write(' — $clip');
  }
  var out = buf.toString().trim();
  if (out.length > kWikiInjectCharCap) {
    out = out.substring(0, kWikiInjectCharCap).trim();
  }
  return out;
}

/// Named tiddler body, title first, clipped. Empty on miss / `$:/` / junk.
String tiddlyPageText(
  TiddlyIndex index,
  String title, {
  int clipChars = kWikiInjectCharCap,
}) {
  final want = title.trim().toLowerCase();
  if (want.isEmpty || want.startsWith('\$:/')) return '';
  for (final t in index.tiddlers) {
    if (t.title.toLowerCase() != want) continue;
    var out = '${t.title}\n${t.text}'.trim();
    if (clipChars > 0 && out.length > clipChars) {
      out = out.substring(0, clipChars).trim();
    }
    return out;
  }
  return '';
}

bool _isTiddlerStoreScript(String attrs, String body) {
  final a = attrs.toLowerCase();
  if (a.contains('tiddlywiki-tiddler-store')) return true;
  if (!a.contains('application/json')) return false;
  final t = body.trim();
  return t.startsWith('[') && t.contains('"title"') && t.contains('"text"');
}

bool _isJunkTiddler({required String title, required String type}) {
  if (title.isEmpty) return true;
  final lower = title.toLowerCase();
  if (lower.contains('medialibrary') || lower.contains('media library')) {
    return true;
  }
  for (final ext in _junkExt) {
    if (lower.endsWith(ext)) return true;
  }
  final t = type.toLowerCase();
  if (t.startsWith('image/') ||
      t.startsWith('audio/') ||
      t.startsWith('video/')) {
    return true;
  }
  if (t == 'text/css' || t.contains('javascript')) return true;
  if (t == 'application/octet-stream') return true;
  return false;
}

String _plainTiddlerText(String raw, String type) {
  final t = type.toLowerCase();
  if (t.startsWith('image/') ||
      t.startsWith('audio/') ||
      t.startsWith('video/')) {
    return '';
  }
  var s = wikiHtmlToPlain(raw);
  s = s.replaceAll(_transcludeRe, ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  return s;
}
