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

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/services/chat/web_search_tools.dart';
import 'package:front_porch_ai/services/chat/wiki_search_tools.dart';

/// Where a catalog entry came from. Never shown to the model.
enum ToolSource { inProcess, userCard }

/// One entry in the flat catalog the model sees.
class CatalogTool {
  const CatalogTool({
    required this.name,
    required this.description,
    required this.parameters,
    required this.source,
    this.card,
  });

  final String name;
  final String description;
  final Map<String, dynamic> parameters;
  final ToolSource source;
  final UserToolCard? card;

  Map<String, dynamic> toOpenAiTool() => {
    'type': 'function',
    'function': {
      'name': name,
      'description': description,
      'parameters': parameters,
    },
  };
}

/// A tool omitted from the catalog, and why.
class CatalogExclusion {
  const CatalogExclusion({
    required this.toolName,
    required this.reason,
    this.owner = '',
  });

  final String toolName;
  final String reason;
  final String owner;
}

/// Unified flat catalog: in-process tools plus user recipe cards.
class CatalogBuildResult {
  const CatalogBuildResult({required this.tools, required this.exclusions});

  final List<CatalogTool> tools;
  final List<CatalogExclusion> exclusions;

  List<Map<String, dynamic>> toOpenAiTools() => [
    for (final t in tools) t.toOpenAiTool(),
  ];

  CatalogTool? lookup(String name) {
    for (final t in tools) {
      if (t.name == name) return t;
    }
    return null;
  }

  bool get isEmpty => tools.isEmpty;
  bool get hasSearch => tools.any((t) => t.name == kWebSearchToolName);
  bool get hasWiki => tools.any(
    (t) => t.name == kWikiSearchToolName || t.name == kWikiPageToolName,
  );
}

/// In-process `web_search` as a catalog entry. Source is never shown to the model.
CatalogTool inProcessWebSearchTool() {
  final fn = kWebSearchTools.first['function'] as Map<String, dynamic>;
  return CatalogTool(
    name: kWebSearchToolName,
    description: fn['description']?.toString() ?? '',
    parameters: Map<String, dynamic>.from(fn['parameters'] as Map),
    source: ToolSource.inProcess,
  );
}

/// In-process `wiki_search`. Same catalog round as web_search; only advertised
/// when this chat has a wiki URL.
CatalogTool inProcessWikiSearchTool() {
  final fn = kWikiSearchTools.first['function'] as Map<String, dynamic>;
  return CatalogTool(
    name: kWikiSearchToolName,
    description: fn['description']?.toString() ?? '',
    parameters: Map<String, dynamic>.from(fn['parameters'] as Map),
    source: ToolSource.inProcess,
  );
}

/// In-process `wiki_page` (get_article). Same gate as wiki_search.
CatalogTool inProcessWikiPageTool() {
  final fn = kWikiPageTools.first['function'] as Map<String, dynamic>;
  return CatalogTool(
    name: kWikiPageToolName,
    description: fn['description']?.toString() ?? '',
    parameters: Map<String, dynamic>.from(fn['parameters'] as Map),
    source: ToolSource.inProcess,
  );
}

/// HTTP recipe card from `<library>/tools/*.json`. Invalid cards never
/// become a [UserToolCard] — [parse] returns null and they stay off the menu.
class UserToolCard {
  const UserToolCard({
    required this.name,
    required this.description,
    required this.parameters,
    required this.method,
    required this.url,
    this.headers = const {},
    this.bodyTemplate,
  });

  final String name;
  final String description;
  final Map<String, dynamic> parameters;
  final String method;
  final Uri url;
  final Map<String, String> headers;
  final Map<String, dynamic>? bodyTemplate;

  CatalogTool toCatalogTool() => CatalogTool(
    name: name,
    description: description,
    parameters: parameters,
    source: ToolSource.userCard,
    card: this,
  );

  /// Null when the JSON is not an enabled HTTP recipe the host can advertise.
  static UserToolCard? parse(Object? raw) {
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    if (map['enabled'] == false) return null;
    final name = map['name']?.toString().trim() ?? '';
    if (!_kToolName.hasMatch(name)) return null;
    final urlRaw = map['url']?.toString().trim() ?? '';
    final url = Uri.tryParse(urlRaw);
    if (url == null ||
        url.host.isEmpty ||
        (url.scheme != 'http' && url.scheme != 'https')) {
      return null;
    }
    final method = (map['method']?.toString() ?? 'POST').trim().toUpperCase();
    if (method.isEmpty) return null;
    final parameters = _objectSchema(map['parameters']);
    final headers = <String, String>{};
    final rawHeaders = map['headers'];
    if (rawHeaders is Map) {
      rawHeaders.forEach((k, v) {
        if (k is String && v != null) headers[k] = v.toString();
      });
    }
    Map<String, dynamic>? bodyTemplate;
    final body = map['body'];
    if (body is Map) {
      bodyTemplate = Map<String, dynamic>.from(body);
    }
    return UserToolCard(
      name: name,
      description: map['description']?.toString() ?? '',
      parameters: parameters,
      method: method,
      url: url,
      headers: headers,
      bodyTemplate: bodyTemplate,
    );
  }
}

final _kToolName = RegExp(r'^[a-zA-Z0-9_-]{1,64}$');

Map<String, dynamic> _objectSchema(Object? raw) {
  if (raw is Map) {
    final type = raw['type']?.toString() ?? 'object';
    if (type == 'object') return Map<String, dynamic>.from(raw);
  }
  return const {'type': 'object', 'properties': <String, dynamic>{}};
}

String? _lastCatalogLogSig;

/// Merge in-process tools with user recipe cards. In-process names win.
CatalogBuildResult buildToolCatalog({
  required List<CatalogTool> inProcess,
  List<CatalogTool> userCards = const [],
}) {
  final tools = <CatalogTool>[];
  final exclusions = <CatalogExclusion>[];
  final taken = <String, String>{};

  for (final t in inProcess) {
    tools.add(t);
    taken[t.name] = 'in-process';
  }
  for (final t in userCards) {
    if (t.name.isEmpty) continue;
    final owner = taken[t.name];
    if (owner != null) {
      final reason = 'name collision with $owner; first wins, omitted';
      exclusions.add(
        CatalogExclusion(toolName: t.name, reason: reason, owner: owner),
      );
      debugPrint('[Tools] catalog exclude ${t.name}: $reason');
      continue;
    }
    taken[t.name] = 'user-card';
    tools.add(t);
  }

  final sig =
      '${tools.length}|${exclusions.length}|'
      '${[for (final t in tools) t.name].join(',')}';
  if (sig != _lastCatalogLogSig) {
    _lastCatalogLogSig = sig;
    debugPrint(
      '[Tools] catalog built: ${tools.length} tool(s), '
      '${exclusions.length} excluded',
    );
  }
  return CatalogBuildResult(tools: tools, exclusions: exclusions);
}

/// Recipe cards share the web_search window: first user send only.
/// Continue, regen, guests, autonomous, and xml-only backends stay offline.
bool shouldAdvertiseUserTools({
  required bool hasCards,
  required bool directUserSend,
  required bool continueMode,
  required bool toolsUnsupported,
  bool autonomousMode = false,
}) {
  return hasCards &&
      directUserSend &&
      !continueMode &&
      !autonomousMode &&
      !toolsUnsupported;
}
