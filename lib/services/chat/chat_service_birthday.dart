// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// One live birthday journal card per owner. Heat from the story clock.
// Optional frozen outing when Objectives is on. Not Planner Today.

part of '../chat_service.dart';

final Expando<DateTime> _birthdaySyncDayOf = Expando();
final Expando<String> _birthdaySyncKeyOf = Expando();

extension ChatServiceBirthday on ChatService {
  bool _isLiteCard(CharacterCard card) =>
      card.frontPorchExtensions?.tier == 'lite';

  List<CharacterCard> _birthdayDiaryOwners() {
    if (_activeGroup != null) {
      return [
        for (final c in _groupCharacters)
          if (!_isLiteCard(c)) c,
      ];
    }
    final one = _activeCharacter;
    if (one == null || _isLiteCard(one)) return const [];
    return [one];
  }

  /// Empty on the member is a clear. Do not inherit the library
  /// card — 1:1 empty retires, group empty must stay empty.
  String _birthdayIsoFor(CharacterCard card) {
    return (card.frontPorchExtensions?.birthday ?? '').trim();
  }

  /// Plant or rewrite the live birthday cards, then maybe a frozen outing.
  /// Journal off = no cards. Planner Today is not used.
  ///
  /// Same story day and quiet days far from every birthday skip the rewrite.
  /// Heat only moves once a date is in the two-week window, on the day, or
  /// in the two-day afterglow — Continue does not tick the clock, so it skips.
  Future<void> _ensureBirthdayState() async {
    final sid = _currentSessionId;
    if (sid == null) return;
    if (!_storageService.memorySettings.journalEnabled) return;
    final now = _timeService.clock;
    final userName = _userPersonaService.persona.name;
    final userIso = _userPersonaService.persona.birthday;
    final maxCards = _storageService.memorySettings.journalMaxCards;
    final owners = _birthdayDiaryOwners();
    final ownerIsos = [for (final card in owners) _birthdayIsoFor(card)];
    final isos = [userIso, ...ownerIsos];
    final identityKey =
        '$sid|u=$userIso|n=$userName|'
        '${[for (var i = 0; i < owners.length; i++) '${_getCharacterIdFromCard(owners[i])}:${ownerIsos[i]}'].join(',')}';
    if (!BirthdayMath.needsRefresh(
      lastSyncDay: _birthdaySyncDayOf[this],
      lastIdentityKey: _birthdaySyncKeyOf[this] ?? '',
      identityKey: identityKey,
      now: now,
      isos: isos,
    )) {
      return;
    }

    for (var i = 0; i < owners.length; i++) {
      final card = owners[i];
      final ownerId = _getCharacterIdFromCard(card);
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
    _birthdaySyncDayOf[this] = StoryClock.dateOnly(now);
    _birthdaySyncKeyOf[this] = identityKey;
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
      await _journalStore.upsertBirthdayCard(
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
    await _journalStore.upsertBirthdayCard(
      sessionId: sessionId,
      characterId: ownerId,
      ownerKey: key,
      iso: reading.birth.iso,
      content: line,
      heat: reading.heat,
      maxCards: maxCards,
    );
    await _maybePlantBirthdayOuting(
      ownerId: ownerId,
      card: card,
      reading: reading,
      self: self,
      userName: userName,
      now: now,
    );
  }

  Future<void> _maybePlantBirthdayOuting({
    required String ownerId,
    required CharacterCard card,
    required BirthdayReading reading,
    required bool self,
    required String userName,
    required DateTime now,
  }) async {
    if (!objectivesActive) return;
    final year = BirthdayMath.occurrenceYear(reading, now);
    final title = BirthdayMath.objectiveTitleFor(
      monthDay: reading.birth.monthDay,
      year: year,
      self: self,
      userName: userName,
    );
    final existing = await _db.getObjectivesForCharacter(
      ownerId,
      chatId: _currentSessionId,
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
        await _db.updateObjective(
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
    if (retired) await _loadActiveObjectives();
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
    if (activeSecondaries.length >= kMaxSecondaryObjectives) return;

    final newId = const Uuid().v4();
    final tasks = [
      for (final t in BirthdayMath.outingTasks(
        card: card,
        self: self,
        userName: userName,
      ))
        {'description': t, 'completed': false},
    ];
    await _db.insertObjective(
      ObjectivesCompanion.insert(
        id: newId,
        characterId: ownerId,
        objective: title,
        tasks: drift.Value(jsonEncode(tasks)),
        chatId: drift.Value(_currentSessionId),
        active: const drift.Value(true),
        isPrimary: const drift.Value(false),
      ),
    );
    await _loadActiveObjectives();
  }
}
