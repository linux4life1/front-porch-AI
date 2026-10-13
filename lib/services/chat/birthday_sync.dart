// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// One live birthday journal card per owner. Heat from the story clock.
// Optional frozen outing when Objectives is on. Not Planner Today.

import 'dart:convert';

import 'package:drift/drift.dart' as drift;
import 'package:front_porch_ai/database/database.dart' hide AvatarImage, World;
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/birthday.dart';
import 'package:front_porch_ai/services/chat/journal_store.dart';
import 'package:front_porch_ai/services/chat/story_clock.dart';
import 'package:front_porch_ai/services/chat/time_service.dart';
import 'package:front_porch_ai/services/persona/user_persona.dart';
import 'package:front_porch_ai/services/storage/settings/memory_settings.dart';
import 'package:uuid/uuid.dart';

class BirthdaySync {
  BirthdaySync({
    required this.currentSessionId,
    required this.memorySettings,
    required this.time,
    required this.persona,
    required this.cast,
    required this.characterIdFor,
    required this.journalStore,
    required this.objectivesActive,
    required this.db,
    required this.reloadActiveObjectives,
    required this.maxSecondaryObjectives,
  });

  final String? Function() currentSessionId;
  final MemorySettings Function() memorySettings;
  final TimeService Function() time;
  final UserPersona Function() persona;

  /// Group members in a group, else the 1:1 character (when set).
  final Iterable<CharacterCard> Function() cast;
  final String Function(CharacterCard card) characterIdFor;
  final JournalStore Function() journalStore;

  /// The live Objectives AND (per-chat switch AND global).
  final bool Function() objectivesActive;
  final AppDatabase Function() db;
  final Future<void> Function() reloadActiveObjectives;
  final int maxSecondaryObjectives;

  DateTime? _syncDay;
  String _syncKey = '';

  static bool _isLiteCard(CharacterCard card) =>
      card.frontPorchExtensions?.tier == 'lite';

  List<CharacterCard> _diaryOwners() => [
    for (final c in cast())
      if (!_isLiteCard(c)) c,
  ];

  /// Empty on the member is a clear. Do not inherit the library
  /// card — 1:1 empty retires, group empty must stay empty.
  static String _birthdayIsoFor(CharacterCard card) {
    return (card.frontPorchExtensions?.birthday ?? '').trim();
  }

  /// Plant or rewrite the live birthday cards, then maybe a frozen outing.
  /// Journal off = no cards. Planner Today is not used.
  ///
  /// Same story day and quiet days far from every birthday skip the rewrite.
  /// Heat only moves once a date is in the two-week window, on the day, or
  /// in the two-day afterglow — Continue does not tick the clock, so it skips.
  Future<void> ensure() async {
    final sid = currentSessionId();
    if (sid == null) return;
    if (!memorySettings().journalEnabled) return;
    final now = time().clock;
    final userName = persona().name;
    final userIso = persona().birthday;
    final maxCards = memorySettings().journalMaxCards;
    final owners = _diaryOwners();
    final ownerIsos = [for (final card in owners) _birthdayIsoFor(card)];
    final isos = [userIso, ...ownerIsos];
    final identityKey =
        '$sid|u=$userIso|n=$userName|'
        '${[for (var i = 0; i < owners.length; i++) '${characterIdFor(owners[i])}:${ownerIsos[i]}'].join(',')}';
    if (!BirthdayMath.needsRefresh(
      lastSyncDay: _syncDay,
      lastIdentityKey: _syncKey,
      identityKey: identityKey,
      now: now,
      isos: isos,
    )) {
      return;
    }

    for (var i = 0; i < owners.length; i++) {
      final card = owners[i];
      final ownerId = characterIdFor(card);
      if (ownerId.isEmpty) continue;
      await _upsertOwnerBirthday(
        sessionId: sid,
        ownerId: ownerId,
        card: card,
        iso: ownerIsos[i],
        self: true,
        userName: userName,
        now: now,
        maxCards: maxCards,
      );
      await _upsertOwnerBirthday(
        sessionId: sid,
        ownerId: ownerId,
        card: card,
        iso: userIso,
        self: false,
        userName: userName,
        now: now,
        maxCards: maxCards,
      );
    }
    _syncDay = StoryClock.dateOnly(now);
    _syncKey = identityKey;
  }

  Future<void> _upsertOwnerBirthday({
    required String sessionId,
    required String ownerId,
    required CharacterCard card,
    required String iso,
    required bool self,
    required String userName,
    required DateTime now,
    required int maxCards,
  }) async {
    final key = self ? 'self' : 'user';
    final reading = BirthdayMath.read(iso, now);
    if (reading == null) {
      await journalStore().upsertBirthdayCard(
        sessionId: sessionId,
        characterId: ownerId,
        ownerKey: key,
        iso: '',
        content: '',
        heat: 0,
        maxCards: maxCards,
      );
      return;
    }
    final line = BirthdayMath.diaryLine(
      reading: reading,
      self: self,
      userName: userName,
    );
    await journalStore().upsertBirthdayCard(
      sessionId: sessionId,
      characterId: ownerId,
      ownerKey: key,
      iso: reading.birth.iso,
      content: line,
      heat: reading.heat,
      maxCards: maxCards,
    );
    await _maybePlantOuting(
      ownerId: ownerId,
      card: card,
      reading: reading,
      self: self,
      userName: userName,
      now: now,
    );
  }

  Future<void> _maybePlantOuting({
    required String ownerId,
    required CharacterCard card,
    required BirthdayReading reading,
    required bool self,
    required String userName,
    required DateTime now,
  }) async {
    if (!objectivesActive()) return;
    final year = BirthdayMath.occurrenceYear(reading, now);
    final title = BirthdayMath.objectiveTitleFor(
      monthDay: reading.birth.monthDay,
      year: year,
      self: self,
      userName: userName,
    );
    final existing = await db().getObjectivesForCharacter(
      ownerId,
      chatId: currentSessionId(),
    );
    var retired = false;
    final leftover = <Objective>[];
    for (final o in existing) {
      if (!o.active) continue;
      if (BirthdayMath.outingShouldRetire(
        o.objective,
        phase: reading.phase,
        occurrenceYear: year,
        monthDay: reading.birth.monthDay,
      )) {
        await db().updateObjective(
          ObjectivesCompanion(
            id: drift.Value(o.id),
            active: const drift.Value(false),
          ),
        );
        retired = true;
        continue;
      }
      leftover.add(o);
    }
    if (retired) await reloadActiveObjectives();
    if (reading.phase != BirthdayPhase.upcoming &&
        reading.phase != BirthdayPhase.today) {
      return;
    }
    for (final o in leftover) {
      if (BirthdayMath.isBirthdayObjective(
        o.objective,
        year: year,
        monthDay: reading.birth.monthDay,
      )) {
        return;
      }
    }
    final activeSecondaries = [
      for (final o in leftover)
        if (!o.isPrimary) o,
    ];
    if (activeSecondaries.length >= maxSecondaryObjectives) return;

    final newId = const Uuid().v4();
    final tasks = [
      for (final t in BirthdayMath.outingTasks(
        card: card,
        self: self,
        userName: userName,
      ))
        {'description': t, 'completed': false},
    ];
    await db().insertObjective(
      ObjectivesCompanion.insert(
        id: newId,
        characterId: ownerId,
        objective: title,
        tasks: drift.Value(jsonEncode(tasks)),
        chatId: drift.Value(currentSessionId()),
        active: const drift.Value(true),
        isPrimary: const drift.Value(false),
      ),
    );
    await reloadActiveObjectives();
  }
}
