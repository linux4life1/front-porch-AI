// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The identity facts pass: the model answers words, Dart decides numbers.
// A birthday must agree with the Age field on the day it is read, bond and
// trust must come from the four warmth bands, a stranger stays a stranger,
// and intimate lists exist only on an 18+ run.

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chargen/chargen.dart';
import 'package:front_porch_ai/services/chat/chat.dart'
    show formatWorkHoursRange, parseWorkHoursRange;

final _today = DateTime(2026, 10, 13);

IdentityFacts _parse(
  Map<String, dynamic> raw, {
  String age = '29',
  String relationship = 'old friend',
  bool nsfw = false,
}) => parseIdentityFacts(
  raw,
  nsfw: nsfw,
  age: age,
  relationship: relationship,
  name: 'Mira Holt',
  today: _today,
);

/// Whole years between [birthday] and [_today], computed the long way.
int _ageOn(String birthday) {
  final b = DateTime.parse(birthday);
  var years = _today.year - b.year;
  if (_today.month < b.month ||
      (_today.month == b.month && _today.day < b.day)) {
    years--;
  }
  return years;
}

void main() {
  group('birthday agrees with Age', () {
    test('a birthday earlier in the year', () {
      final f = _parse({'birthday_month': 3, 'birthday_day': 14});
      expect(f.birthday, '1997-03-14');
      expect(_ageOn(f.birthday), 29);
    });

    test('a birthday later in the year is a year earlier', () {
      final f = _parse({'birthday_month': 12, 'birthday_day': 2});
      expect(f.birthday, '1996-12-02');
      expect(_ageOn(f.birthday), 29);
    });

    test('a birthday today counts as had', () {
      final f = _parse({'birthday_month': 10, 'birthday_day': 13});
      expect(_ageOn(f.birthday), 29);
    });

    test('Feb 29 becomes Feb 28; an impossible date is blank', () {
      expect(
        _parse({'birthday_month': 2, 'birthday_day': 29}).birthday,
        '1997-02-28',
      );
      expect(_parse({'birthday_month': 4, 'birthday_day': 31}).birthday, '');
      expect(_parse({'birthday_month': 13, 'birthday_day': 1}).birthday, '');
    });

    test('words and strings are read; Age text keeps its number', () {
      final f = _parse({
        'birthday_month': 'March',
        'birthday_day': '14',
      }, age: '29 years old');
      expect(f.birthday, '1997-03-14');
    });

    test('birth_year only when Age is blank', () {
      expect(
        _parse({
          'birthday_month': 5,
          'birthday_day': 1,
          'birth_year': 1990,
        }, age: '').birthday,
        '1990-05-01',
      );
      expect(
        _parse({
          'birthday_month': 5,
          'birthday_day': 1,
          'birth_year': 1990,
        }).birthday,
        '1997-05-01',
      );
      expect(
        _parse({
          'birthday_month': 5,
          'birthday_day': 1,
          'birth_year': 1990,
        }, age: 'ageless').birthday,
        '',
      );
    });
  });

  group('bond and trust', () {
    const bands = {
      'strangers': (0, 0),
      'warm': (15, 15),
      'guarded': (0, 0),
      'cold': (-15, -10),
    };
    for (final e in bands.entries) {
      test('${e.key} maps to ${e.value}', () {
        final f = _parse({'relationship_warmth': e.key});
        expect(f.warmth, e.key);
        expect((f.shortTermBond, f.trustLevel), e.value);
      });
    }

    for (final rel in ['', 'Stranger', 'strangers', 'None']) {
      test('relationship "$rel" forces strangers', () {
        final f = _parse({'relationship_warmth': 'warm'}, relationship: rel);
        expect(f.warmth, 'strangers');
        expect((f.shortTermBond, f.trustLevel), (0, 0));
      });
    }

    test('an unknown warmth word is strangers', () {
      expect(_parse({'relationship_warmth': 'besotted'}).warmth, 'strangers');
    });
  });

  test('creator notes turn the name into {{char}}', () {
    final f = _parse({
      'creator_notes': 'Mira Holt maps a coast that moves. Holt never rests.',
    });
    expect(
      f.creatorNotes,
      '{{char}} maps a coast that moves. {{char}} never '
      'rests.',
    );
  });

  test('intimate lists only when 18+ is on', () {
    final raw = {
      'intimate_into': ['slow mornings'],
      'intimate_not_into': ['an audience'],
    };
    expect(_parse(raw).intimateInto, isEmpty);
    expect(_parse(raw).intimateNotInto, isEmpty);
    expect(_parse(raw, nsfw: true).intimateInto, ['slow mornings']);
    expect(_parse(raw, nsfw: true).intimateNotInto, ['an audience']);
  });

  test('no job means no hours, brief or days', () {
    final f = _parse({
      'occupation': '',
      'occupation_brief': 'Nothing.',
      'hours': '09:00-17:00',
      'work_days': [1, 2],
    });
    expect(f.hours, '');
    expect(f.occupationBrief, '');
    expect(f.workDays, isNull);
  });

  test('hours are written the way the picker writes them; days by name', () {
    final f = _parse({
      'occupation': 'ferry pilot',
      'hours': '22:00-06:00',
      'work_days': ['Friday', 'sat', 7],
    });
    expect(f.hours, formatWorkHoursRange(22 * 60, 6 * 60));
    expect(parseWorkHoursRange(f.hours), (22 * 60, 6 * 60));
    expect(f.workDays, [5, 6, 7]);
  });

  test('salvages a text answer with a stray quote', () {
    const raw =
        'Here:\n{"occupation": "the "best" ferry pilot", "birthday_month": 3, '
        '"birthday_day": 14, "likes": ["salt wind"], "relationship_warmth": '
        '"warm"';
    final f = parseIdentityFacts(
      raw,
      nsfw: false,
      age: '29',
      relationship: 'old friend',
      today: _today,
    );
    expect(f.occupation, 'the "best" ferry pilot');
    expect(f.birthday, '1997-03-14');
    expect(f.likes, ['salt wind']);
    expect(f.warmth, 'warm');
  });

  test('JSON round trip is lossless', () {
    final f = _parse({
      'birthday_month': 3,
      'birthday_day': 14,
      'occupation': 'cartographer',
      'hours': '07:00-15:30',
      'work_days': [1, 2],
      'current_task': 'Finish the chart.',
      'relationship_warmth': 'cold',
      'ambitions': ['a boat'],
      'plan_lines': ['Sell charts.'],
      'likes': ['salt'],
      'dislikes': ['fog'],
      'creator_notes': 'A mapmaker.',
    });
    expect(IdentityFacts.fromJson(f.toJson()).toJson(), f.toJson());
  });

  test('applyIdentityFacts writes the facts and leaves settings alone', () {
    final card = CharacterCard(
      name: 'Mira',
      creatorNotes: 'mine',
      systemPrompt: 'sys',
      frontPorchExtensions: FrontPorchExtensions(
        chaosModeEnabled: true,
        likes: const ['old like'],
      ),
    );
    applyIdentityFacts(
      card,
      _parse({
        'birthday_month': 3,
        'birthday_day': 14,
        'relationship_warmth': 'warm',
        'ambitions': ['a boat'],
        'creator_notes': 'A mapmaker.',
      }),
    );
    final ext = card.frontPorchExtensions!;
    expect(ext.birthday, '1997-03-14');
    expect(ext.ambitions, ['a boat']);
    expect(ext.likes, ['old like'], reason: 'an empty read keeps the list');
    expect((ext.shortTermBond, ext.trustLevel), (15, 15));
    expect(ext.chaosModeEnabled, isTrue);
    expect(card.systemPrompt, 'sys');
    expect(card.creatorNotes, 'A mapmaker.');
  });

  test('a read with 18+ off clears intimate lists the card still had', () {
    final card = CharacterCard(
      name: 'Mira',
      frontPorchExtensions: FrontPorchExtensions(
        intimateInto: const ['slow mornings'],
        intimateNotInto: const ['an audience'],
      ),
    );
    applyIdentityFacts(
      card,
      _parse({
        'intimate_into': ['should not land'],
        'ambitions': ['a boat'],
      }),
      nsfw: false,
    );
    final ext = card.frontPorchExtensions!;
    expect(ext.intimateInto, isEmpty);
    expect(ext.intimateNotInto, isEmpty);
    expect(ext.ambitions, ['a boat']);
  });
}
