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

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/eval_lane_params.dart';
import 'package:front_porch_ai/services/chat/tool_catalog.dart';
import 'package:front_porch_ai/services/chat/web_search_tools.dart';
import 'package:front_porch_ai/services/chat/wiki_search_tools.dart';
import 'package:front_porch_ai/services/llm_service.dart';

/// Instruction for the web-search doorbell. It sees [lastUserMessage] only.
const String kWebSearchDoorbellSystem =
    'The message below is the user\'s latest line and nothing else. '
    'If it names a person, place, work, character, title, or fact that '
    'should be looked up, call web_search with a short search-box query '
    '(the name, plus at most one extra word). '
    'If nothing needs a lookup, do not call a tool.';

/// Eval-lane params for the web-search check. No character card, no
/// transcript, no images. Wiki and recipe cards do not use this.
GenerationParams webSearchDoorbellParams(String lastUserMessage) {
  return evalLaneParams(
    prompt: lastUserMessage.trim(),
    systemPrompt: kWebSearchDoorbellSystem,
  );
}

/// Instruction for the wiki doorbell. It sees [wikiWindow] only: the older
/// user line, the character reply, and the latest user line.
const String kWikiDoorbellSystem =
    'The lines below are only the previous user line, the character '
    'reply, and the latest user line — whichever of those three exist. '
    'Resolve pronouns such as "that ritual" or "her sister" from this '
    'window. If a person, place, ritual, term, or title should be looked '
    'up in the wiki, call wiki_search with a short search-box query, then '
    'wiki_page with the title. If nothing needs a lookup, do not call a tool.';

/// Eval-lane params for the wiki check. No character card, no full transcript.
GenerationParams wikiDoorbellParams(String wikiWindow) {
  return evalLaneParams(
    prompt: wikiWindow.trim(),
    systemPrompt: kWikiDoorbellSystem,
  );
}

/// One story line the wiki window may keep. Status banners are not lines.
class WikiWindowTurn {
  const WikiWindowTurn({
    required this.speaker,
    required this.text,
    required this.isUser,
  });

  final String speaker;
  final String text;
  final bool isUser;
}

/// Older user line, the one character reply after it, then the latest user
/// line. Missing pieces are left out. A second character reply is not pulled.
List<WikiWindowTurn> selectWikiLookupWindow(
  List<WikiWindowTurn> chronological,
) {
  var latestUser = -1;
  for (var i = chronological.length - 1; i >= 0; i--) {
    final turn = chronological[i];
    if (turn.isUser && turn.text.trim().isNotEmpty) {
      latestUser = i;
      break;
    }
  }
  if (latestUser < 0) return const [];

  var character = -1;
  for (var i = latestUser - 1; i >= 0; i--) {
    final turn = chronological[i];
    if (!turn.isUser && turn.text.trim().isNotEmpty) {
      character = i;
      break;
    }
  }

  var olderUser = -1;
  if (character >= 0) {
    for (var i = character - 1; i >= 0; i--) {
      final turn = chronological[i];
      if (turn.isUser && turn.text.trim().isNotEmpty) {
        olderUser = i;
        break;
      }
    }
  }

  return [
    if (olderUser >= 0) chronological[olderUser],
    if (character >= 0) chronological[character],
    chronological[latestUser],
  ];
}

/// `Speaker: text` lines, oldest first. Empty when there is no user line.
String formatWikiLookupWindow(List<WikiWindowTurn> chronological) {
  final selected = selectWikiLookupWindow(chronological);
  if (selected.isEmpty) return '';
  return [
    for (final turn in selected)
      '${turn.speaker.trim().isEmpty ? (turn.isUser ? 'User' : 'Character') : turn.speaker.trim()}: ${turn.text.trim()}',
  ].join('\n');
}

/// Wiki window from a live transcript. Status banners and blank lines are
/// skipped. The character line keeps that message's speaker name.
String wikiWindowFromMessages(List<ChatMessage> messages) {
  final turns = <WikiWindowTurn>[];
  for (final message in messages) {
    if (message.isStatusBanner) continue;
    final text = message.promptText.trim();
    if (text.isEmpty) continue;
    turns.add(
      WikiWindowTurn(
        speaker: message.sender,
        text: text,
        isUser: message.isUser,
      ),
    );
  }
  return formatWikiLookupWindow(turns);
}

bool _isWikiTool(String name) =>
    name == kWikiSearchToolName || name == kWikiPageToolName;

/// One doorbell trip: which tools, and which prompt they are allowed to see.
class CatalogDoorbellJob {
  const CatalogDoorbellJob({required this.params, required this.catalog});

  final GenerationParams params;
  final CatalogBuildResult catalog;
}

/// Web search gets [lastUserMessage]. Wiki gets [wikiWindow] (two user lines
/// and one character reply). Recipe cards keep [mouth]. An empty user line
/// skips the search trip; an empty wiki window skips the wiki trip.
List<CatalogDoorbellJob> catalogDoorbellJobs({
  required GenerationParams mouth,
  required CatalogBuildResult catalog,
  required String lastUserMessage,
  String wikiWindow = '',
}) {
  final search = <CatalogTool>[];
  final wiki = <CatalogTool>[];
  final rest = <CatalogTool>[];
  for (final tool in catalog.tools) {
    if (tool.name == kWebSearchToolName) {
      search.add(tool);
    } else if (_isWikiTool(tool.name)) {
      wiki.add(tool);
    } else {
      rest.add(tool);
    }
  }
  final jobs = <CatalogDoorbellJob>[];
  final line = lastUserMessage.trim();
  if (search.isNotEmpty && line.isNotEmpty) {
    jobs.add(
      CatalogDoorbellJob(
        params: webSearchDoorbellParams(line),
        catalog: CatalogBuildResult(tools: search, exclusions: const []),
      ),
    );
  }
  final window = wikiWindow.trim();
  if (wiki.isNotEmpty && window.isNotEmpty) {
    jobs.add(
      CatalogDoorbellJob(
        params: wikiDoorbellParams(window),
        catalog: CatalogBuildResult(tools: wiki, exclusions: const []),
      ),
    );
  }
  if (rest.isNotEmpty) {
    jobs.add(
      CatalogDoorbellJob(
        params: mouth,
        catalog: CatalogBuildResult(
          tools: rest,
          exclusions: catalog.exclusions,
        ),
      ),
    );
  }
  return jobs;
}
