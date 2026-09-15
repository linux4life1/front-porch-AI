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

import 'package:front_porch_ai/services/chat/web_search_tools.dart';

/// OpenAI-shaped `wiki_search`. Advertised only when this chat has a wiki
/// URL and the turn is a direct user send (same window as `web_search`).
const String kWikiSearchToolName = 'wiki_search';

const List<Map<String, dynamic>> kWikiSearchTools = [
  {
    'type': 'function',
    'function': {
      'name': kWikiSearchToolName,
      'description':
          'Look up a person, place, ritual, or term from this chat\'s '
          'wiki — fiction and lore included. Call when you are not certain. '
          'Never invent. Returns matching titles and short clips as plain '
          'text. Then call wiki_page with a title to open the article. '
          'Put a short search-box query in `query` (the title or name, '
          'plus at most one extra word). Do not paste the scene or dialogue.',
      'parameters': {
        'type': 'object',
        'properties': {
          'query': {
            'type': 'string',
            'maxLength': kWebSearchQueryMaxChars,
            'description':
                'Short search-box text: the name of the person, place, '
                'ritual, or thing, plus at most one extra word.',
          },
        },
        'required': ['query'],
      },
    },
  },
];

/// OpenAI-shaped `wiki_page` (get_article). Same catalog window as
/// `wiki_search`. One tool, MediaWiki or Tiddly backend.
const String kWikiPageToolName = 'wiki_page';

const List<Map<String, dynamic>> kWikiPageTools = [
  {
    'type': 'function',
    'function': {
      'name': kWikiPageToolName,
      'description':
          'Open one article from this chat\'s wiki by title. Use after '
          'wiki_search when you have the page name. Fiction and lore '
          'included. Never invent. Returns the article clip as plain text. '
          'Pass `title` (or `page`).',
      'parameters': {
        'type': 'object',
        'properties': {
          'title': {
            'type': 'string',
            'maxLength': kWebSearchQueryMaxChars,
            'description': 'Exact article / tiddler title to open.',
          },
          'page': {
            'type': 'string',
            'maxLength': kWebSearchQueryMaxChars,
            'description': 'Alias for title.',
          },
        },
      },
    },
  },
];
