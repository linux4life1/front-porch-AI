// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// At work is occupation + hours + the period. Fail closed.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/chat/presence_derive.dart';
import 'package:front_porch_ai/ui/chat_components/sidebar/character_state/presence_word.dart';

PresenceWhere d({
  String occupation = 'clerk',
  String hours = '9-5',
  String timeOfDay = 'afternoon',
  bool isGroup = false,
  bool inScene = true,
}) =>
    derivePresence(
      occupation: occupation,
      hours: hours,
      timeOfDay: timeOfDay,
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
    expect(d(hours: '9-5', timeOfDay: 'afternoon'), PresenceWhere.atWork);
  });

  test('9-5 in the evening is With you', () {
    expect(d(hours: '9-5', timeOfDay: 'evening'), PresenceWhere.withYou);
  });

  test('mornings at late_morning is At work', () {
    expect(
      d(occupation: 'teacher', hours: 'mornings', timeOfDay: 'late_morning'),
      PresenceWhere.atWork,
    );
  });

  test('evenings at afternoon is With you', () {
    expect(
      d(occupation: 'bartender', hours: 'evenings', timeOfDay: 'afternoon'),
      PresenceWhere.withYou,
    );
  });

  test('group member not in scene is Away', () {
    expect(
      d(hours: '9-5', timeOfDay: 'evening', isGroup: true, inScene: false),
      PresenceWhere.away,
    );
  });

  test('1:1 not-in-scene is Away', () {
    expect(
      d(hours: '9-5', timeOfDay: 'evening', isGroup: false, inScene: false),
      PresenceWhere.away,
    );
  });

  test('1:1 on shift is At work', () {
    expect(
      d(hours: '9-5', timeOfDay: 'afternoon', isGroup: false, inScene: true),
      PresenceWhere.atWork,
    );
  });

  test('9am-5pm in the morning is At work', () {
    expect(d(hours: '9am-5pm', timeOfDay: 'morning'), PresenceWhere.atWork);
  });

  test('hh:mm range uses the period default hour', () {
    expect(
      d(hours: '09:00–17:00', timeOfDay: 'afternoon'),
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
    final skipSrc =
        File('lib/services/chat/chat_service_turn_flow.dart').readAsStringSync();
    final skipFn = RegExp(
      r'bool _groupSpeakerSkips\(CharacterCard card\) \{([\s\S]*?)\n  \}',
    ).firstMatch(skipSrc);
    expect(skipFn, isNotNull, reason: '_groupSpeakerSkips must stay in turn_flow');
    final skipBody = skipFn!.group(1)!;
    // Goes red if the 1:1 guard is removed from the real method.
    expect(
      skipBody,
      contains('if (_activeGroup == null) return false;'),
    );
    expect(skipBody, contains('return groupTurnSkips(where);'));

    final genSrc =
        File('lib/services/chat/chat_service_generation.dart').readAsStringSync();
    final genGate = RegExp(
      r'if \(guestSpeaker == null &&\s+'
      r'_activeGroup != null &&\s+'
      r'mode != GenerationMode\.continue_ &&\s+'
      r'_groupSpeakerSkips\(speakingCharacter\)\)',
    ).firstMatch(genSrc);
    expect(
      genGate,
      isNotNull,
      reason: 'generation must call _groupSpeakerSkips only in a group',
    );

    final atWork = derivePresence(
      occupation: 'clerk',
      hours: '9-5',
      timeOfDay: 'afternoon',
      inScene: true,
    );
    final away = derivePresence(
      occupation: 'clerk',
      hours: '9-5',
      timeOfDay: 'evening',
      inScene: false,
    );
    expect(atWork, PresenceWhere.atWork);
    expect(away, PresenceWhere.away);

    bool groupSpeakerSkips({
      required bool activeGroup,
      required PresenceWhere where,
    }) {
      if (!activeGroup) return false;
      return groupTurnSkips(where);
    }

    expect(groupSpeakerSkips(activeGroup: false, where: atWork), isFalse);
    expect(groupSpeakerSkips(activeGroup: false, where: away), isFalse);
    expect(groupSpeakerSkips(activeGroup: true, where: atWork), isTrue);
    expect(groupSpeakerSkips(activeGroup: true, where: away), isTrue);
    expect(
      groupSpeakerSkips(activeGroup: true, where: PresenceWhere.withYou),
      isFalse,
    );
  });

  test('hoursMatch 9-5 morning stays true', () {
    expect(hoursMatch('9-5', 'morning'), isTrue);
  });

  test('empty group ext falls back to library 9-5 morning At work', () {
    final work = workFieldsForGroupMember(
      copyOccupation: '',
      copyHours: '',
      libraryOccupation: 'meteorologist',
      libraryHours: '9-5',
    );
    expect(
      derivePresence(
        occupation: work.occupation,
        hours: work.hours,
        timeOfDay: 'morning',
        inScene: false,
      ),
      PresenceWhere.atWork,
    );
  });
}
