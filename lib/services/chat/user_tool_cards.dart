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
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'package:front_porch_ai/services/chat/prompt_injection/search_injection.dart';
import 'package:front_porch_ai/services/chat/tool_catalog.dart';

const Duration kUserToolTimeout = Duration(seconds: 60);
const int kUserToolRawByteCap = 64 * 1024;

/// Outcome of one recipe-card HTTP call. [text] is already clipped.
class UserToolHttpResult {
  const UserToolHttpResult({required this.ok, required this.text});

  final bool ok;
  final String text;
}

typedef UserToolHttpSend =
    Future<UserToolHttpResult> Function({
      required String method,
      required Uri url,
      required Map<String, String> headers,
      required String body,
    });

/// Copy `.json` files into [toolsDir]. Other extensions are skipped.
/// Overwrites a same-named card. Returns how many files landed.
int copyJsonFilesIntoTools(Directory toolsDir, Iterable<String> sourcePaths) {
  try {
    toolsDir.createSync(recursive: true);
  } catch (e) {
    debugPrint('[Tools] could not create ${toolsDir.path}: $e');
    return 0;
  }
  var copied = 0;
  for (final rawPath in sourcePaths) {
    final src = File(rawPath);
    final name = src.uri.pathSegments.isEmpty ? '' : src.uri.pathSegments.last;
    if (name.isEmpty || !name.toLowerCase().endsWith('.json')) continue;
    if (name.contains('..') || name.contains('/') || name.contains('\\')) {
      continue;
    }
    if (!src.existsSync()) continue;
    try {
      src.copySync('${toolsDir.path}/$name');
      copied++;
    } catch (e) {
      debugPrint('[Tools] copy $name failed: $e');
    }
  }
  return copied;
}

/// Load enabled HTTP recipe cards from `<library>/tools/`. Creates the
/// folder if it is missing. Junk files are skipped, never executed.
List<UserToolCard> loadUserToolCards(Directory toolsDir) {
  try {
    toolsDir.createSync(recursive: true);
  } catch (e) {
    debugPrint('[Tools] could not create ${toolsDir.path}: $e');
    return const [];
  }
  final out = <UserToolCard>[];
  final seen = <String>{};
  List<FileSystemEntity> entries;
  try {
    entries = toolsDir.listSync(followLinks: false);
  } catch (e) {
    debugPrint('[Tools] could not list ${toolsDir.path}: $e');
    return const [];
  }
  for (final entity in entries) {
    if (entity is! File) continue;
    final name = entity.uri.pathSegments.isEmpty
        ? ''
        : entity.uri.pathSegments.last;
    if (!name.toLowerCase().endsWith('.json')) continue;
    String raw;
    try {
      raw = entity.readAsStringSync();
    } catch (e) {
      debugPrint('[Tools] skip $name: $e');
      continue;
    }
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (e) {
      debugPrint('[Tools] skip $name: invalid JSON ($e)');
      continue;
    }
    final card = UserToolCard.parse(decoded);
    if (card == null) {
      debugPrint('[Tools] skip $name: not an enabled HTTP recipe');
      continue;
    }
    if (!seen.add(card.name)) {
      debugPrint('[Tools] skip $name: duplicate name ${card.name}');
      continue;
    }
    out.add(card);
  }
  return out;
}

/// POST JSON `{tool, arguments}` (or the card's body map). Never evaluates
/// scripts. [send] is the unit-test seam — production uses package:http.
Future<UserToolHttpResult> executeUserToolCard(
  UserToolCard card,
  Map<String, dynamic> arguments, {
  UserToolHttpSend? send,
}) async {
  final body = jsonEncode(_requestBody(card, arguments));
  final headers = <String, String>{
    'Content-Type': 'application/json',
    ...card.headers,
  };
  debugPrint(
    '[Tools] HTTP ${card.method} ${card.url} tool=${card.name} '
    'bodyChars=${body.length}',
  );
  try {
    final result = send != null
        ? await send(
            method: card.method,
            url: card.url,
            headers: headers,
            body: body,
          ).timeout(kUserToolTimeout)
        : await _httpSend(
            method: card.method,
            url: card.url,
            headers: headers,
            body: body,
          ).timeout(kUserToolTimeout);
    final clipped = SearchInjection.clipSnippet(result.text);
    return UserToolHttpResult(
      ok: result.ok && clipped.isNotEmpty,
      text: clipped,
    );
  } catch (e) {
    debugPrint('[Tools] HTTP THREW tool=${card.name}: $e');
    return const UserToolHttpResult(ok: false, text: '');
  }
}

Map<String, dynamic> _requestBody(
  UserToolCard card,
  Map<String, dynamic> arguments,
) {
  final template = card.bodyTemplate;
  if (template == null) {
    return {'tool': card.name, 'arguments': arguments};
  }
  return _substitute(template, arguments);
}

Map<String, dynamic> _substitute(
  Map<String, dynamic> template,
  Map<String, dynamic> arguments,
) {
  final out = <String, dynamic>{};
  template.forEach((key, value) {
    if (value is String) {
      out[key] = value.replaceAllMapped(RegExp(r'\{\{(\w+)\}\}'), (m) {
        final name = m.group(1);
        return arguments[name]?.toString() ?? '';
      });
    } else {
      out[key] = value;
    }
  });
  return out;
}

Future<UserToolHttpResult> _httpSend({
  required String method,
  required Uri url,
  required Map<String, String> headers,
  required String body,
}) async {
  final request = http.Request(method, url)
    ..headers.addAll(headers)
    ..body = body
    ..followRedirects = false
    ..maxRedirects = 0;
  final client = http.Client();
  try {
    final streamed = await client.send(request);
    final chunks = <int>[];
    await for (final chunk in streamed.stream) {
      if (chunks.length + chunk.length > kUserToolRawByteCap) {
        chunks.addAll(chunk.take(kUserToolRawByteCap - chunks.length));
        break;
      }
      chunks.addAll(chunk);
    }
    final text = utf8.decode(chunks, allowMalformed: true);
    final ok = streamed.statusCode >= 200 && streamed.statusCode < 300;
    debugPrint(
      '[Tools] HTTP status=${streamed.statusCode} bodyChars=${text.length}',
    );
    return UserToolHttpResult(ok: ok, text: ok ? text : '');
  } finally {
    client.close();
  }
}
