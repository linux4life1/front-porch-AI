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

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:drift/drift.dart';
import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/persona/persona.dart';

export 'package:front_porch_ai/services/persona/user_persona.dart';

class UserPersonaService extends ChangeNotifier {
  AppDatabase _db;
  List<UserPersona> _personas = [];

  /// Who you are IN THE CHAT YOU ARE IN. Runtime only — never persisted here,
  /// because it belongs to the session, not to the app (Sessions.userPersonaId
  /// is where it lives). Set from the session on open, from [_defaultPersonaId]
  /// on a fresh chat, and by the in-chat switcher.
  String _activePersonaId = '';

  /// Who a NEW chat starts as when nobody picks. Persisted (the Personas
  /// isActive column) and changed only by a deliberate user action on the
  /// Persona page — so it stays a default rather than drifting to whichever
  /// chat was opened last.
  ///
  /// These were ONE value until 2026-08-04, and merging them was a quiet data
  /// bug: opening a chat re-pointed the "default" at that chat's persona, and
  /// picking a persona on the Persona page re-stamped whatever chat happened to
  /// still be loaded (every _saveChat writes the live persona, including saves
  /// from background passes the user never triggered). The app's own persona
  /// picker states the intent — "a fresh chat must never silently inherit
  /// whatever persona the last one used" — which only holds if the default
  /// cannot be moved by simply reading a chat.
  String _defaultPersonaId = '';

  List<UserPersona> get personas => List.unmodifiable(_personas);

  UserPersona get persona => _resolve(_activePersonaId);

  /// The persona a new chat is seeded with. Shown as "Default" on the Persona
  /// page; [persona] is what the current chat is actually speaking as.
  UserPersona get defaultPersona => _resolve(_defaultPersonaId);

  String get defaultPersonaId => defaultPersona.id;

  UserPersona _resolve(String id) {
    if (_personas.isEmpty) {
      return UserPersona(id: 'default', name: 'User');
    }
    return _personas.firstWhere(
      (p) => p.id == id,
      orElse: () => _personas.first,
    );
  }

  UserPersonaService(this._db) {
    _loadPersonas();
  }

  /// Update the database reference (e.g. after cloud sync replaces the DB file).
  void updateDatabase(AppDatabase db) {
    _db = db;
  }

  Future<void> _loadPersonas() async {
    try {
      // One read, as before: deleted rows keep their ids, so they raise the
      // id floor too, then drop out of the list. A second query here delayed
      // the load into a create or import already under way.
      final stored = await _db.select(_db.personas).get();
      notePersonaIds(stored.map((row) => row.id));
      final dbPersonas = stored.where((row) => row.deletedAt == null).toList();

      if (dbPersonas.isEmpty) {
        // Create default persona
        final defaultId = newPersonaId();
        await _db.insertPersona(
          PersonasCompanion.insert(
            id: defaultId,
            name: const Value('User'),
            isActive: const Value(true),
          ),
        );
        _personas = [UserPersona(id: defaultId, name: 'User')];
        _defaultPersonaId = defaultId;
        _activePersonaId = defaultId;
      } else {
        // Note: the dormant Personas.learnedFacts DB column is deliberately
        // not read — the old auto-fact feature was replaced by the per-chat
        // Journal (fresh start; docs/design/journal-memory.md §3).
        _personas = dbPersonas
            .map(
              (p) => UserPersona(
                id: p.id,
                title: p.title,
                name: p.name,
                persona: p.persona,
                avatarPath: p.avatarPath,
                birthday: p.birthday ?? '',
              ),
            )
            .toList();

        final storedDefault = dbPersonas.where((p) => p.isActive).firstOrNull;
        _defaultPersonaId = storedDefault?.id ?? _personas.first.id;
        _activePersonaId = _defaultPersonaId;
      }

      notifyListeners();
    } catch (e) {
      debugPrint('Error loading personas from DB: $e');
    }
  }

  /// Adds a persona and returns its id. With [activate] (the default) it
  /// becomes both the default for new chats and who you are right now; a
  /// converted character passes false and only joins the list.
  Future<String> createPersona(
    String title,
    String name,
    String persona,
    String? avatarPath, {
    String birthday = '',
    bool activate = true,
  }) async {
    final id = newPersonaId();

    await _db.insertPersona(
      PersonasCompanion.insert(
        id: id,
        title: Value(title),
        name: Value(name),
        persona: Value(persona),
        avatarPath: Value(avatarPath),
        birthday: Value(birthday.isEmpty ? null : birthday),
        isActive: Value(activate),
      ),
    );

    // Deactivate others
    if (activate) await _db.setActivePersona(id);

    final newPersona = UserPersona(
      id: id,
      title: title,
      name: name,
      persona: persona,
      avatarPath: avatarPath,
      birthday: birthday,
    );
    _personas.add(newPersona);
    // Creating a persona is deliberate enough to mean both: it becomes the
    // default for new chats and who you are right now.
    if (activate) {
      _defaultPersonaId = id;
      _activePersonaId = id;
    }
    notifyListeners();
    return id;
  }

  Future<void> updatePersona(UserPersona updatedPersona) async {
    final index = _personas.indexWhere((p) => p.id == updatedPersona.id);
    if (index != -1) {
      _personas[index] = updatedPersona;

      await _db.updatePersona(
        PersonasCompanion(
          id: Value(updatedPersona.id),
          title: Value(updatedPersona.title),
          name: Value(updatedPersona.name),
          persona: Value(updatedPersona.persona),
          avatarPath: Value(updatedPersona.avatarPath),
          birthday: Value(
            updatedPersona.birthday.isEmpty ? null : updatedPersona.birthday,
          ),
          isActive: Value(updatedPersona.id == _defaultPersonaId),
        ),
      );

      notifyListeners();
    }
  }

  Future<void> deletePersona(String id) async {
    if (_personas.length <= 1) return; // Prevent deleting the last one

    _personas.removeWhere((p) => p.id == id);
    await _db.deletePersonaById(id);

    if (_defaultPersonaId == id) {
      _defaultPersonaId = _personas.first.id;
      await _db.setActivePersona(_defaultPersonaId);
    }
    // A chat speaking as the deleted persona falls back to the default rather
    // than to "whatever sorts first".
    if (_activePersonaId == id) {
      _activePersonaId = _defaultPersonaId;
    }

    notifyListeners();
  }

  /// Speak as [id] from here on — a CHAT-scoped change. Deliberately does not
  /// persist: the binding that outlives the app is Sessions.userPersonaId,
  /// written when the chat saves. Use [setDefaultPersona] for the preference.
  Future<void> setActivePersona(String id) async {
    if (_personas.any((p) => p.id == id)) {
      _activePersonaId = id;
      notifyListeners();
    }
  }

  /// Change which persona NEW chats start as. Never touches the chat in front
  /// of you — that is the whole point of the split; see [_defaultPersonaId].
  Future<void> setDefaultPersona(String id) async {
    if (_personas.any((p) => p.id == id)) {
      _defaultPersonaId = id;
      await _db.setActivePersona(id);
      notifyListeners();
    }
  }

  void notify() => notifyListeners();

  /// Export all personas + active ID to a JSON file for cloud sync.
  Future<void> exportToFile(String filePath) async {
    final data = PersonaFileCodec.encodeCloud(
      defaultPersonaId: _defaultPersonaId,
      personas: _personas,
    );
    final file = File(filePath);
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(data));
  }

  /// Import persona(s) from a JSON file. Supports SillyTavern, native,
  /// TavernAI V2 / Backyard, and generic name+description payloads (see
  /// [PersonaFileCodec.importAll]). Returns the first imported persona,
  /// or null on failure.
  Future<UserPersona?> importFromJsonFile(
    String filePath, {
    String? avatarSaveDir,
  }) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        debugPrint('[Persona:Import] File not found: $filePath');
        return null;
      }
      final data = jsonDecode(await file.readAsString());
      if (data is! Map<String, dynamic>) {
        debugPrint(
          '[Persona:Import] Unexpected JSON root type: ${data.runtimeType}',
        );
        return null;
      }
      return await PersonaFileCodec.importAll(
        data,
        add: _addImportedPersona,
        avatarSaveDir: avatarSaveDir,
      );
    } catch (e) {
      debugPrint('[Persona:Import] Error importing persona JSON: $e');
      return null;
    }
  }

  /// Persist an imported persona and make it the default + current persona
  /// (same reasoning as [createPersona]). A clashing id gets a fresh one.
  Future<void> _addImportedPersona(UserPersona p) async {
    final existingIds = _personas.map((e) => e.id).toSet();
    final toInsert = existingIds.contains(p.id)
        ? UserPersona(
            id: newPersonaId(),
            title: p.title,
            name: p.name,
            persona: p.persona,
            avatarPath: p.avatarPath,
            birthday: p.birthday,
          )
        : p;

    await _db.insertPersona(_insertCompanion(toInsert, isActive: true));
    await _db.setActivePersona(toInsert.id);
    _personas.add(toInsert);
    _defaultPersonaId = toInsert.id;
    _activePersonaId = toInsert.id;
    notify();
  }

  PersonasCompanion _insertCompanion(UserPersona p, {required bool isActive}) {
    return PersonasCompanion.insert(
      id: p.id,
      title: Value(p.title),
      name: Value(p.name),
      persona: Value(p.persona),
      avatarPath: Value(p.avatarPath),
      birthday: Value(p.birthday.isEmpty ? null : p.birthday),
      isActive: Value(isActive),
    );
  }

  /// Export multiple personas to a JSON file in SillyTavern compliant format.
  Future<void> exportPersonasToSTFormat(
    List<String> personaIds,
    String filePath,
  ) async {
    final selected = [
      for (final id in personaIds)
        _personas.firstWhere((e) => e.id == id, orElse: () => persona),
    ];
    final data = PersonaFileCodec.encodeSillyTavern(selected);
    final file = File(filePath);
    await file.parent.create(recursive: true);
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(data));
  }

  /// Reload personas from DB (e.g. after cloud sync import).
  Future<void> reload() async {
    await _loadPersonas();
  }
}
