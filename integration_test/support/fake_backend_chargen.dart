// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Canned replies for the AI Character Creator's stages, routed by the
// sentence each prompt is built around (gen_prompts, gen_interview_steps,
// gen_identity_facts, gen_lore_steps, gen_porch_life), so a web create runs
// the real pipeline end to end under the browser suite. Greetings are not
// answered here: they fall through to the chat reply (FPAI_REPLY), which is
// what the Greetings journeys assert on. Tool calls are refused by the fake
// as a whole, so the facts and Porch Life passes take their JSON text floor.

import 'dart:convert';

/// Written into a steered profile rewrite, so a journey can see it landed.
const kChargenSteeredMarker = 'rewritten the way the author asked';

/// The chargen stage [content] asks for and its reply pieces, or null when
/// the prompt is not one of the creator's stages.
({String stage, List<String> pieces})? chargenReply(String content) {
  bool has(String marker) => content.contains(marker);
  if (has('Create a roleplay character card as a single JSON object')) {
    return (stage: 'chargen-base', pieces: [_baseCard]);
  }
  if (has('Answer each question in first person, fully in-character') &&
      has('Question: ')) {
    return (
      stage: 'chargen-interview',
      pieces: [
        'I keep the light because somebody has to, and I say what I mean.',
      ],
    );
  }
  if (has('You have just completed an in-character interview with')) {
    final steered = has('== DIRECTION FROM THE AUTHOR ==');
    final json = jsonEncode(steered ? _steeredProfile : _profile);
    // In pieces, a little apart: the phone shows the description arriving
    // before the personality starts.
    final third = json.length ~/ 3;
    return (
      stage: steered ? 'chargen-rewrite' : 'chargen-enrich',
      pieces: [
        json.substring(0, third),
        json.substring(third, third * 2),
        json.substring(third * 2),
      ],
    );
  }
  if (has('Read the facts this character profile implies for')) {
    return (stage: 'chargen-facts', pieces: [jsonEncode(_facts)]);
  }
  if (has('Write example dialogue exchanges')) {
    return (
      stage: 'chargen-dialogue',
      pieces: [
        '<START>\n{{user}}: Is the light still on?\n'
            '{{char}}: Every night. Mind the third step, it is loose.',
      ],
    );
  }
  if (has('Generate WORLD-BUILDING lorebook entries')) {
    return (stage: 'chargen-lorebook', pieces: [jsonEncode(_lorebook)]);
  }
  if (has('Generate exactly') && has('meeting scenarios')) {
    return (
      stage: 'chargen-scenarios',
      pieces: [
        jsonEncode({
          'scenarios': [
            '{{user}} rows out to the rock in a fog with a letter for {{char}}.',
            '{{user}} finds {{char}} mending nets on the harbor wall at dawn.',
            '{{user}} is the relief keeper, a week early and soaked.',
            '{{user}} brings the winter supplies on the last boat out.',
            '{{user}} hears the bell ring at noon, which it never does.',
          ],
        }),
      ],
    );
  }
  if (has('Seed Porch Life identity lists for')) {
    return (
      stage: 'chargen-porch-life',
      pieces: [
        jsonEncode({
          'worn': ['oilskin coat'],
          'carrying': ['brass key'],
          'character_emotion': 'calm',
          'time_of_day': 'evening',
        }),
      ],
    );
  }
  if (has('Write an image generation prompt for an illustration')) {
    return (
      stage: 'chargen-image',
      pieces: ['a lighthouse keeper in an oilskin coat, lamp room, dusk'],
    );
  }
  if (has('Generate ONLY the following fields for a roleplay character')) {
    return (stage: 'chargen-fields', pieces: [_baseCard]);
  }
  return null;
}

final _baseCard = jsonEncode({
  'description':
      '{{char}} keeps the lamp at Gull Point, a lighthouse on a wet rock two '
      'miles off the harbor town, tall and salt-weathered.',
  'personality':
      'Dry, watchful and slow to warm; {{char}} hides care inside practical '
      'help and is embarrassed by thanks.',
  'scenario':
      'A storm has closed the harbor for three days and {{user}} has been '
      'sleeping in the lamp room since washing up on the jetty.',
  'first_message': '*{{char}} trims the wick.*',
  'example_dialogue': '{{user}}: Hello\n{{char}}: Mind the steps.',
  'system_prompt': '',
  'tags': ['lighthouse'],
  'image_prompt': 'a lighthouse keeper at dusk',
  'lorebook': {'entries': <Object>[]},
});

const _profile = {
  'description':
      '{{char}} is tall and windburnt, with salt-cracked hands, dark hair she '
      'cuts herself and a coat that smells of lamp oil and tar.',
  'personality':
      'Blunt and exact; {{char}} answers questions with questions and hides '
      'care inside practical help, a dry coat or a full kettle.',
  'scenario':
      'The storm has closed the harbor for three days and the lamp room is '
      'the only warm place left on the rock.',
};

const _steeredProfile = {
  'description':
      '{{char}}, $kChargenSteeredMarker, is tall and windburnt, with '
      'salt-cracked hands and a coat that smells of lamp oil and tar.',
  'personality':
      'Colder now: {{char}} says little, means all of it, and keeps every '
      'kindness hidden behind a chore she pretends is for herself.',
  'scenario':
      'The storm has closed the harbor for three days and the lamp room is '
      'the only warm place left on the rock.',
};

const _facts = {
  'birthday_month': 3,
  'birthday_day': 14,
  'birth_year': 1990,
  'occupation': 'lighthouse keeper',
  'occupation_brief': 'Keeps the lamp lit and logs every ship.',
  'hours': '18:00-06:00',
  'work_days': [1, 2, 3, 4, 5, 6, 7],
  'current_task': 'Trim the wick before the storm gets worse.',
  'relationship_warmth': 'strangers',
  'ambitions': ['keep the light one more winter'],
  'plan_lines': ['Fix the bell before the inspector comes.'],
  'likes': ['salt wind', 'strong tea'],
  'dislikes': ['fog', 'being thanked'],
  'creator_notes':
      'A keeper who will tell you how foolish you were, then '
      'pour the tea.',
};

const _lorebook = {
  'lorebook': [
    {
      'name': 'Gull Point',
      'category': 'premise',
      'key': 'rock, lighthouse, sea',
      'secondary': '',
      'content': 'A wet rock two miles off the harbor town, lit every night.',
    },
    {
      'name': 'The Harbor Town',
      'category': 'location',
      'key': 'harbor, town',
      'secondary': '',
      'content': 'Gulls, tar and a bell that rings at dusk.',
    },
  ],
};
