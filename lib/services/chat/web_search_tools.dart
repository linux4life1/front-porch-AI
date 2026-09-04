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

/// OpenAI-shaped `web_search` tool. Advertised on the chat-generation
/// tools round-trip when the per-chat switch is on and a search key is set.
const String kWebSearchToolName = 'web_search';

const List<Map<String, dynamic>> kWebSearchTools = [
  {
    'type': 'function',
    'function': {
      'name': kWebSearchToolName,
      'description':
          'Look up a term, person, place, show, character, or fact you '
          'are not certain of — fiction and lore included, not just '
          'current events. You MUST call this when you do not recognize '
          'something, or for weather, news, prices, sports, or dates. '
          'Never invent. Returns top results as plain text.',
      'parameters': {
        'type': 'object',
        'properties': {
          'query': {'type': 'string', 'description': 'The search query.'},
        },
        'required': ['query'],
      },
    },
  },
];
