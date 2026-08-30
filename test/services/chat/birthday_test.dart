// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/birthday.dart';
import 'package:front_porch_ai/services/chat/episode_crumbs.dart';
import 'package:front_porch_ai/services/chat/journal_physics.dart';
import 'package:front_porch_ai/services/chat/journal_store.dart';

void main() {
  group('BirthdayMath.parse', () {
    test('accepts a full date and rejects Feb 29', () {
      expect(BirthdayMath.parse('1998-03-15')?.iso, '1998-03-15');
      expect(BirthdayMath.parse('1998-02-29'), isNull);
      expect(BirthdayMath.parse('2000-02-29'), isNull);
      expect(BirthdayMath.parse('1998-13-01'), isNull);
      expect(BirthdayMath.parse(''), isNull);
      expect(BirthdayMath.parse('march 15'), isNull);
    });
  });

  group('BirthdayMath.read', () {
    test('age and days-until against the story clock', () {
      final before = BirthdayMath.read(
        '1998-03-15',
        DateTime.utc(2026, 3, 10),
      )!;
      expect(before.age, 27);
      expect(before.daysUntil, 5);
      expect(before.phase, BirthdayPhase.upcoming);
      expect(before.heat, greaterThanOrEqualTo(0.35));

      final day = BirthdayMath.read('1998-03-15', DateTime.utc(2026, 3, 15))!;
      expect(day.age, 28);
      expect(day.daysUntil, 0);
      expect(day.phase, BirthdayPhase.today);
      expect(day.heat, 1.0);

      final after = BirthdayMath.read('1998-03-15', DateTime.utc(2026, 3, 16))!;
      expect(after.age, 28);
      expect(after.phase, BirthdayPhase.justPast);
      expect(after.heat, greaterThanOrEqualTo(0.35));

      final far = BirthdayMath.read('1998-03-15', DateTime.utc(2026, 8, 1))!;
      expect(far.age, 28);
      expect(far.phase, BirthdayPhase.far);
      expect(far.heat, lessThan(0.35));
    });

    test('future birth date is invalid', () {
      expect(BirthdayMath.read('2099-01-01', DateTime.utc(2026, 1, 1)), isNull);
    });

    test('fourteen days out is just hot', () {
      final r = BirthdayMath.read('1998-03-15', DateTime.utc(2026, 3, 1))!;
      expect(r.daysUntil, 14);
      expect(r.heat, closeTo(0.35, 1e-9));
    });
  });

  group('diary line', () {
    test('upcoming says I will be N+1; the day says I turn N', () {
      final upcoming = BirthdayMath.read(
        '1998-03-15',
        DateTime.utc(2026, 3, 10),
      )!;
      expect(
        BirthdayMath.diaryLine(reading: upcoming, self: true, userName: 'Sam'),
        "My birthday is March 15. I'll be 28.",
      );
      final day = BirthdayMath.read('1998-03-15', DateTime.utc(2026, 3, 15))!;
      expect(
        BirthdayMath.diaryLine(reading: day, self: true, userName: 'Sam'),
        'Today I turn 28.',
      );
      final nextYear = BirthdayMath.read(
        '1998-03-15',
        DateTime.utc(2027, 3, 10),
      )!;
      expect(
        BirthdayMath.diaryLine(reading: nextYear, self: true, userName: 'Sam'),
        "My birthday is March 15. I'll be 29.",
      );
    });
  });

  group('physics', () {
    JournalMemoryData card({String? kind, double heat = 0.9}) =>
        JournalMemoryData(
          id: 'x',
          sessionId: 's1',
          characterId: 'mara',
          content: 'c',
          category: 'moment',
          heat: heat,
          accessCount: 0,
          pinned: false,
          dimensions: 0,
          metadata: kind == null ? null : '{"kind":"$kind"}',
          createdAt: DateTime(2026),
          lastAccessedAt: DateTime(2026),
          updatedAt: DateTime(2026),
        );

    test('birthday cards do not cool and stay hot when heat is up', () {
      final b = card(kind: 'birthday', heat: 0.9);
      expect(JournalPhysics.isBirthdayCard(b), isTrue);
      expect(JournalPhysics.cooledHeat(b), 0.9);
      expect(JournalPhysics.isHot(b), isTrue);
      expect(JournalPhysics.isLedgerCard(b), isFalse);
    });
  });

  group('one live card', () {
    late AppDatabase db;
    late JournalStore store;

    setUp(() {
      db = AppDatabase.forTesting();
      store = JournalStore(getDb: () => db);
    });
    tearDown(() async => db.close());

    test('upsert rewrites the same row when they turn 29', () async {
      await store.upsertBirthdayCard(
        sessionId: 's1',
        characterId: 'mara',
        ownerKey: 'self',
        iso: '1998-03-15',
        content: "My birthday is March 15. I'll be 28.",
        heat: 0.7,
        maxCards: 40,
      );
      await store.upsertBirthdayCard(
        sessionId: 's1',
        characterId: 'mara',
        ownerKey: 'self',
        iso: '1998-03-15',
        content: "My birthday is March 15. I'll be 29.",
        heat: 0.8,
        maxCards: 40,
      );
      final cards = await store.cardsFor('s1', 'mara');
      final bdays = cards.where(JournalPhysics.isBirthdayCard).toList();
      expect(bdays, hasLength(1));
      expect(bdays.single.content, contains('29'));
    });

    test('self and user are two cards, not a duplicate of one owner', () async {
      await store.upsertBirthdayCard(
        sessionId: 's1',
        characterId: 'mara',
        ownerKey: 'self',
        iso: '1998-03-15',
        content: 'I am 27. Birthday March 15.',
        heat: 0.12,
        maxCards: 40,
      );
      await store.upsertBirthdayCard(
        sessionId: 's1',
        characterId: 'mara',
        ownerKey: 'user',
        iso: '1995-06-02',
        content: 'Sam is 31. Birthday June 2.',
        heat: 0.12,
        maxCards: 40,
      );
      final cards = await store.cardsFor('s1', 'mara');
      expect(cards.where(JournalPhysics.isBirthdayCard), hasLength(2));
    });
  });

  test('outing tasks come from likes, not a wishlist prompt', () {
    final card = CharacterCard(
      name: 'Mara',
      frontPorchExtensions: FrontPorchExtensions(
        likes: const ['horses', 'rainy movies'],
      ),
    );
    final tasks = BirthdayMath.outingTasks(
      card: card,
      self: true,
      userName: 'Sam',
    );
    expect(tasks, hasLength(2));
    expect(tasks.first, contains('horses'));
    expect(tasks.join(' '), isNot(contains('pony')));
    expect(tasks.join(' '), isNot(contains('diamond')));
  });

  test('cold birthday card does not wake on "age" or "present"', () {
    final card = JournalMemoryData(
      id: 'b',
      sessionId: 's1',
      characterId: 'mara',
      content: 'I am 27. Birthday March 15.',
      category: 'moment',
      heat: 0.12,
      accessCount: 0,
      pinned: false,
      dimensions: 0,
      metadata: '{"kind":"birthday","owner":"self"}',
      createdAt: DateTime(2026),
      lastAccessedAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    expect(
      JournalPhysics.birthdayCardMentioned(card, {'age', 'present'}),
      isFalse,
    );
    expect(JournalPhysics.birthdayCardMentioned(card, {'birthday'}), isTrue);
  });

  test('day-of birthday impulse is silent off the rare roll', () {
    final injected = [
      JournalMemoryData(
        id: 'b',
        sessionId: 's1',
        characterId: 'mara',
        content: 'Today I turn 28.',
        category: 'moment',
        heat: 1.0,
        accessCount: 0,
        pinned: false,
        dimensions: 0,
        metadata: '{"kind":"birthday"}',
        createdAt: DateTime(2026),
        lastAccessedAt: DateTime(2026),
        updatedAt: DateTime(2026),
      ),
    ];
    expect(
      speechImpulse(injected: injected, lastWords: 'hey', seed: 1),
      isNull,
    );
    expect(
      speechImpulse(injected: injected, lastWords: 'hey', seed: 0),
      contains('Today I turn 28'),
    );
  });

  group('needsRefresh', () {
    const iso = '1998-03-15';
    const key = 'k';

    test('same story day skips even inside the heat window', () {
      expect(
        BirthdayMath.needsRefresh(
          lastSyncDay: DateTime.utc(2026, 3, 10, 9),
          lastIdentityKey: key,
          identityKey: key,
          now: DateTime.utc(2026, 3, 10, 18),
          isos: const [iso],
        ),
        isFalse,
      );
    });

    test('far from every birthday skips across quiet days', () {
      expect(
        BirthdayMath.needsRefresh(
          lastSyncDay: DateTime.utc(2026, 8, 1),
          lastIdentityKey: key,
          identityKey: key,
          now: DateTime.utc(2026, 8, 4),
          isos: const [iso],
        ),
        isFalse,
      );
    });

    test('entering the two-week window rewrites', () {
      expect(
        BirthdayMath.needsRefresh(
          lastSyncDay: DateTime.utc(2026, 2, 28),
          lastIdentityKey: key,
          identityKey: key,
          now: DateTime.utc(2026, 3, 1),
          isos: const [iso],
        ),
        isTrue,
      );
    });

    test('daily rewrite while heating, on the day, or afterglow', () {
      expect(
        BirthdayMath.needsRefresh(
          lastSyncDay: DateTime.utc(2026, 3, 10),
          lastIdentityKey: key,
          identityKey: key,
          now: DateTime.utc(2026, 3, 11),
          isos: const [iso],
        ),
        isTrue,
      );
      expect(
        BirthdayMath.needsRefresh(
          lastSyncDay: DateTime.utc(2026, 3, 15),
          lastIdentityKey: key,
          identityKey: key,
          now: DateTime.utc(2026, 3, 16),
          isos: const [iso],
        ),
        isTrue,
      );
    });

    test('identity change rewrites even on the same day', () {
      expect(
        BirthdayMath.needsRefresh(
          lastSyncDay: DateTime.utc(2026, 8, 1),
          lastIdentityKey: key,
          identityKey: 'k2',
          now: DateTime.utc(2026, 8, 1),
          isos: const [iso],
        ),
        isTrue,
      );
    });

    test('first sync and a far year-skip that changes age rewrite', () {
      expect(
        BirthdayMath.needsRefresh(
          lastSyncDay: null,
          lastIdentityKey: key,
          identityKey: key,
          now: DateTime.utc(2026, 8, 1),
          isos: const [iso],
        ),
        isTrue,
      );
      expect(
        BirthdayMath.needsRefresh(
          lastSyncDay: DateTime.utc(2026, 8, 1),
          lastIdentityKey: key,
          identityKey: key,
          now: DateTime.utc(2027, 8, 1),
          isos: const [iso],
        ),
        isTrue,
      );
    });
  });

  test('generation actually calls ensure, not just the helper', () {
    final src = File(
      'lib/services/chat/chat_service_generation_blocks.dart',
    ).readAsStringSync();
    expect(src, contains('await _ensureBirthdayState()'));
  });

  test('ensure stamps last-sync so the next send can skip', () {
    final src = File(
      'lib/services/chat/chat_service_birthday.dart',
    ).readAsStringSync();
    expect(src, contains('BirthdayMath.needsRefresh'));
    expect(
      src,
      contains('_birthdaySyncDayOf[this] = StoryClock.dateOnly(now)'),
    );
    expect(src, contains('_birthdaySyncKeyOf[this] = identityKey'));
  });

  group('BirthdayMath.outingShouldRetire', () {
    const lastYear = 'Birthday (March 15, 2026): have a good birthday with Sam';
    const thisYear = 'Birthday (March 15, 2027): have a good birthday with Sam';
    const other = 'Find the missing keys';

    test('far retires last year so the cap of 4 is free', () {
      expect(
        BirthdayMath.outingShouldRetire(
          lastYear,
          phase: BirthdayPhase.far,
          occurrenceYear: 2027,
          monthDay: 'March 15',
        ),
        isTrue,
      );
    });

    test('afterglow keeps this year', () {
      expect(
        BirthdayMath.outingShouldRetire(
          lastYear,
          phase: BirthdayPhase.justPast,
          occurrenceYear: 2026,
          monthDay: 'March 15',
        ),
        isFalse,
      );
    });

    test('upcoming retires other years, not this year', () {
      expect(
        BirthdayMath.outingShouldRetire(
          lastYear,
          phase: BirthdayPhase.upcoming,
          occurrenceYear: 2027,
          monthDay: 'March 15',
        ),
        isTrue,
      );
      expect(
        BirthdayMath.outingShouldRetire(
          thisYear,
          phase: BirthdayPhase.upcoming,
          occurrenceYear: 2027,
          monthDay: 'March 15',
        ),
        isFalse,
      );
    });

    test('does not retire a non-birthday secondary', () {
      expect(
        BirthdayMath.outingShouldRetire(
          other,
          phase: BirthdayPhase.far,
          occurrenceYear: 2027,
          monthDay: 'March 15',
        ),
        isFalse,
      );
    });
  });

  test('isBirthdayObjective does not prefix-match March 1 onto March 15', () {
    const march15 = 'Birthday (March 15, 2027): have a good birthday with Sam';
    const march1 = 'Birthday (March 1, 2027): have a good birthday with Sam';
    const march20 = 'Birthday (March 20, 2027): have a good birthday with Sam';
    expect(
      BirthdayMath.isBirthdayObjective(march15, monthDay: 'March 1'),
      isFalse,
    );
    expect(
      BirthdayMath.isBirthdayObjective(march15, monthDay: 'March 15'),
      isTrue,
    );
    expect(
      BirthdayMath.isBirthdayObjective(march1, monthDay: 'March 1'),
      isTrue,
    );
    expect(
      BirthdayMath.isBirthdayObjective(march20, monthDay: 'March 2'),
      isFalse,
    );
    expect(
      BirthdayMath.outingShouldRetire(
        march15,
        phase: BirthdayPhase.far,
        occurrenceYear: 2027,
        monthDay: 'March 1',
      ),
      isFalse,
    );
    expect(
      File('lib/services/chat/birthday.dart').readAsStringSync(),
      contains("contains('\$monthDay,')"),
    );
  });

  test('ageAsOfStory prefers the authored ISO date', () {
    expect(BirthdayMath.ageAsOfStory('2020-06-01'), DateTime.utc(2020, 6, 1));
  });

  test('plant retires stale birthday outings before the cap check', () {
    final src = File(
      'lib/services/chat/chat_service_birthday.dart',
    ).readAsStringSync();
    expect(src, contains('BirthdayMath.outingShouldRetire'));
    expect(src, contains('active: const drift.Value(false)'));
    expect(src, contains('kMaxSecondaryObjectives'));
  });

  test('settings persona edit matches Speak as setBirthday on State', () {
    final page = File('lib/ui/pages/user_persona_page.dart').readAsStringSync();
    final form = File(
      'lib/ui/pages/user_persona_page.edit_form.dart',
    ).readAsStringSync();
    expect(
      page,
      contains('void _setBirthday(String v) => setState(() => _birthday = v);'),
    );
    expect(form, contains('onChanged: _setBirthday'));
    expect(form, isNot(contains('setState(() => _birthday')));
  });

  test('create edit persona pass story date into the age line', () {
    expect(
      File(
        'lib/ui/pages/create_character_page.step_realism.dart',
      ).readAsStringSync(),
      contains('birthdayAgeAsOf:'),
    );
    expect(
      File(
        'lib/ui/character_creator/steps/realism_step.dart',
      ).readAsStringSync(),
      contains('birthdayAgeAsOf:'),
    );
    expect(
      File(
        'lib/ui/pages/edit_character_page.tabs_core.dart',
      ).readAsStringSync(),
      contains('birthdayAgeAsOf:'),
    );
    expect(
      File('lib/ui/pages/user_persona_page.edit_form.dart').readAsStringSync(),
      contains('ageAsOf: storyDateOf(context)'),
    );
    expect(
      File(
        'lib/ui/dialogs/user_persona_dialog.edit_form.dart',
      ).readAsStringSync(),
      contains('ageAsOf: storyDateOf(context)'),
    );
  });

  test('persona import insert and duplicate rebuild persist birthday', () {
    final src = File(
      'lib/services/user_persona_service.dart',
    ).readAsStringSync();
    expect(src, contains('birthday: p.birthday'));
    expect(
      src,
      contains(
        'birthday: Value(toInsert.birthday.isEmpty ? null : toInsert.birthday)',
      ),
    );
  });

  test('group empty ISO stays empty, no library fallback', () {
    final src = File(
      'lib/services/chat/chat_service_birthday.dart',
    ).readAsStringSync();
    expect(src, contains('_birthdayIsoFor'));
    expect(src, isNot(contains('originLibraryCardFor')));
  });
}
