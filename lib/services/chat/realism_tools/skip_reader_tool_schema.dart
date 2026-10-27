// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The skip reader's tool (time_skip/skip_reader.dart): did the player's
// line jump story time, how far, and what filled the gap. Registered in
// [realismToolFieldsByTool] so a call converts to the reader's JSON.

import 'package:front_porch_ai/services/chat/realism_tools/realism_tool_names.dart';

/// The scene-time judge's read of a jump the reply narrated
/// (time_service/reply_jump.dart): hours beside its `days_elapsed`, and
/// `lands_at`, the same landing words as the reader's `until`.
const Map<String, Map<String, dynamic>> kJudgedJumpFields = {
  'hours_elapsed': {
    'type': 'integer',
    'description':
        'Whole hours skipped (1-23) ONLY when the reply explicitly narrates '
        'a jump of hours, not days ("six hours later"). 0 otherwise.',
  },
  'lands_at': {
    'type': 'string',
    'description':
        'Only with days_elapsed: the time of day the reply lands at (dawn, '
        'morning, late_morning, afternoon, evening, night, or 24-hour HH:MM). '
        'Blank when it does not say.',
  },
};

final Map<String, Map<String, dynamic>> kSkipReaderFields = {
  'skip': {
    'type': 'boolean',
    'description':
        'True only when the line moves story time forward past the scene: '
        'a time skip, hours or days later, sleeping through the night.',
  },
  'minutes': {
    'type': 'integer',
    'description':
        'Story minutes skipped (8 hours = 480, two weeks = 20160). 0 when '
        'the line only says when it lands, or names no amount.',
  },
  'until': {
    'type': 'string',
    'description':
        'When the skip lands, if the line says: dawn, morning, late_morning, '
        'afternoon, evening, night, or a 24-hour HH:MM. Empty otherwise.',
  },
  'gap': {
    'type': 'string',
    'enum': ['none', 'slept', 'other'],
    'description':
        'What filled the skipped time: slept when they slept through it, '
        'other for anything else, none when there is no skip.',
  },
};

/// The schema list [fireStructuredEval] sends for the skip reader.
final List<Map<String, dynamic>> kSkipReaderTools = [
  {
    'type': 'function',
    'function': {
      'name': kSkipReaderTool,
      'description':
          'Report whether the player\'s line skips story time, and how far.',
      'parameters': {
        'type': 'object',
        'properties': kSkipReaderFields,
        'required': const ['skip', 'minutes', 'until', 'gap'],
      },
    },
  },
];
