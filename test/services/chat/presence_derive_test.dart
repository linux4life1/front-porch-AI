// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// At work is occupation + hours + weekday. Missing workDays is Mon–Fri.
// Fail closed on hours.

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/chat/presence_derive.dart';

const _morning = 9 * 60;
const _lateMorning = 11 * 60 + 30;
const _afternoon = 14 * 60 + 30;
const _evening = 18 * 60 + 30;

PresenceWhere d({
  String occupation = 'clerk',
  String hours = '9-5',
  int clockMinutes = _afternoon,
  int weekday = DateTime.tuesday,
  List<int>? workDays,
  bool isGroup = false,
  bool inScene = true,
}) => derivePresence(
  occupation: occupation,
  hours: hours,
  clockMinutes: clockMinutes,
  weekday: weekday,
  workDays: workDays,
  inScene: inScene,
);

void main() {
  test('empty occupation is With you', () {
    expect(d(occupation: '', hours: '9-5'), PresenceWhere.withYou);
  });

  test('unparseable hours fail closed to With you', () {
    expect(d(occupation: 'baker', hours: 'whenever'), PresenceWhere.withYou);
  });

  test('9-5 in the afternoon is At work', () {
    expect(d(hours: '9-5', clockMinutes: _afternoon), PresenceWhere.atWork);
  });

  test('9-5 in the evening is With you', () {
    expect(d(hours: '9-5', clockMinutes: _evening), PresenceWhere.withYou);
  });

  test('mornings is unparseable and fails closed', () {
    // Period words used to match the named slice of the day. Hours are a
    // clock range now; "mornings" is not one, so At work cannot light.
    expect(
      d(occupation: 'teacher', hours: 'mornings', clockMinutes: _lateMorning),
      PresenceWhere.withYou,
    );
    expect(hoursMatch('mornings', _morning), isFalse);
    expect(parseWorkHoursRange('mornings'), isNull);
  });

  test('evenings at afternoon is With you', () {
    expect(
      d(occupation: 'bartender', hours: 'evenings', clockMinutes: _afternoon),
      PresenceWhere.withYou,
    );
  });

  test('group member not in scene is Away', () {
    expect(
      d(hours: '9-5', clockMinutes: _evening, isGroup: true, inScene: false),
      PresenceWhere.away,
    );
  });

  test('1:1 not-in-scene is Away', () {
    expect(
      d(hours: '9-5', clockMinutes: _evening, isGroup: false, inScene: false),
      PresenceWhere.away,
    );
  });

  test('1:1 on shift is At work', () {
    expect(
      d(hours: '9-5', clockMinutes: _afternoon, isGroup: false, inScene: true),
      PresenceWhere.atWork,
    );
  });

  test('9am-5pm in the morning is At work', () {
    expect(d(hours: '9am-5pm', clockMinutes: _morning), PresenceWhere.atWork);
  });

  test('hh:mm range uses the period default hour', () {
    expect(
      d(hours: '09:00–17:00', clockMinutes: _afternoon),
      PresenceWhere.atWork,
    );
  });

  test('group At work skips the turn', () {
    expect(groupTurnSkips(PresenceWhere.atWork), isTrue);
    expect(groupTurnSkips(PresenceWhere.away), isTrue);
    expect(groupTurnSkips(PresenceWhere.withYou), isFalse);
  });

  test('empty stance is not Away', () {
    expect(stanceSaysAway(''), isFalse);
    expect(stanceSaysAway('  '), isFalse);
  });

  test('here-words stay in scene', () {
    expect(stanceSaysAway('standing by the porch rail'), isFalse);
  });

  test('left-the and next-room mark Away', () {
    expect(stanceSaysAway('She left the kitchen'), isTrue);
    expect(stanceSaysAway('in the next room'), isTrue);
    expect(stanceSaysAway('out of sight down the hall'), isTrue);
  });

  test('1:1 Away and At work never skip; group Away and At work do', () {
    final atWork = derivePresence(
      occupation: 'clerk',
      hours: '9-5',
      clockMinutes: _afternoon,
      weekday: DateTime.tuesday,
      inScene: true,
    );
    final away = derivePresence(
      occupation: 'clerk',
      hours: '9-5',
      clockMinutes: _evening,
      weekday: DateTime.tuesday,
      inScene: false,
    );
    expect(atWork, PresenceWhere.atWork);
    expect(away, PresenceWhere.away);
    expect(groupTurnSkips(atWork), isTrue);
    expect(groupTurnSkips(away), isTrue);
    expect(groupTurnSkips(PresenceWhere.withYou), isFalse);
  });

  test('hoursMatch 9-5 at 9:00 stays true', () {
    expect(hoursMatch('9-5', _morning), isTrue);
    expect(hoursMatch('9-5', 8 * 60), isFalse);
  });

  test('formatWorkHoursRange writes the card string the parser reads', () {
    expect(formatWorkHoursRange(9 * 60, 17 * 60), '9am–5pm');
    expect(formatWorkHoursRange(9 * 60 + 30, 17 * 60 + 15), '9:30am–5:15pm');
    expect(parseWorkHoursRange('9am–5pm'), (9 * 60, 17 * 60));
    expect(parseWorkHoursRange('9:30am–5:15pm'), (9 * 60 + 30, 17 * 60 + 15));
    expect(parseWorkHoursRange('whenever'), isNull);
    expect(parseWorkHoursRange('dawn–dusk'), isNull);
  });

  test('9:30am start is after 9:00 and on the clock at 10:00', () {
    expect(hoursMatch('9:30am–5pm', _morning), isFalse);
    expect(hoursMatch('9:30am–5pm', 10 * 60), isTrue);
    expect(hoursMatch('9:30am–5pm', _lateMorning), isTrue);
  });

  test('empty group ext falls back to library 9-5 morning At work', () {
    final work = workFieldsForGroupMember(
      copyOccupation: '',
      copyHours: '',
      copyOccupationBrief: '',
      libraryOccupation: 'meteorologist',
      libraryHours: '9-5',
      libraryOccupationBrief: 'Reads the sky from the station roof',
    );
    expect(work.occupationBrief, 'Reads the sky from the station roof');
    expect(
      derivePresence(
        occupation: work.occupation,
        hours: work.hours,
        clockMinutes: _morning,
        weekday: DateTime.tuesday,
        inScene: false,
      ),
      PresenceWhere.atWork,
    );
  });

  test('missing workDays on Saturday afternoon is With you', () {
    expect(
      d(weekday: DateTime.saturday, clockMinutes: _afternoon),
      PresenceWhere.withYou,
    );
  });

  test('missing workDays on Tuesday afternoon is At work', () {
    expect(
      d(weekday: DateTime.tuesday, clockMinutes: _afternoon),
      PresenceWhere.atWork,
    );
  });

  test('every-day list is At work on Saturday', () {
    expect(
      d(
        weekday: DateTime.saturday,
        workDays: const [1, 2, 3, 4, 5, 6, 7],
        clockMinutes: _afternoon,
      ),
      PresenceWhere.atWork,
    );
  });

  test('written empty workDays is never at work', () {
    expect(
      d(
        weekday: DateTime.tuesday,
        workDays: const [],
        clockMinutes: _afternoon,
      ),
      PresenceWhere.withYou,
    );
  });

  test('overnight Friday shift is still on Saturday 1am', () {
    expect(
      d(
        hours: '10pm–2am',
        weekday: DateTime.saturday,
        clockMinutes: 60,
        workDays: kDefaultWorkDays,
      ),
      PresenceWhere.atWork,
    );
  });

  test('Saturday-only night shift is not at work Saturday 1am', () {
    expect(
      d(
        hours: '10pm–2am',
        weekday: DateTime.saturday,
        clockMinutes: 60,
        workDays: const [DateTime.saturday],
      ),
      PresenceWhere.withYou,
    );
  });

  test('group library fallback copies workDays', () {
    final work = workFieldsForGroupMember(
      copyOccupation: '',
      copyHours: '',
      copyWorkDays: null,
      libraryOccupation: 'bartender',
      libraryHours: '10pm–2am',
      libraryWorkDays: const [DateTime.friday, DateTime.saturday],
    );
    expect(work.workDays, [DateTime.friday, DateTime.saturday]);
  });

  test('copy with its own hours keeps missing workDays (Mon–Fri)', () {
    final work = workFieldsForGroupMember(
      copyOccupation: 'clerk',
      copyHours: '9-5',
      copyWorkDays: null,
      libraryWorkDays: const [DateTime.saturday],
    );
    expect(work.workDays, isNull);
    expect(
      d(hours: work.hours, weekday: DateTime.saturday, workDays: work.workDays),
      PresenceWhere.withYou,
    );
  });

  test('parseWorkDaysField missing vs empty vs junk', () {
    expect(parseWorkDaysField(null, present: false), isNull);
    expect(parseWorkDaysField(const [], present: true), isEmpty);
    expect(parseWorkDaysField(const [1, 2, 99, '3'], present: true), [1, 2, 3]);
    expect(parseWorkDaysField(const [99, 'nope'], present: true), isNull);
    expect(parseWorkDaysField('weekdays', present: true), isNull);
  });

  test('resolveWorkDays missing is Mon–Fri, empty stays empty', () {
    expect(resolveWorkDays(null), kDefaultWorkDays);
    expect(resolveWorkDays(const []), isEmpty);
  });
}
