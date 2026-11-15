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

import 'dart:io';

import 'package:front_porch_ai/services/services.dart';

/// Persona list + CRUD for the web persona surfaces. Every write goes through
/// the same [UserPersonaService] the desktop uses.
class ChatPersonas {
  ChatPersonas(this._personas, this._chat, this._notify);

  final UserPersonaService? _personas;
  final ChatService _chat;
  final void Function() _notify;

  /// All user personas for the web persona surfaces.
  ///
  /// Two flags, because there are two distinct answers: `default` is who a NEW
  /// chat starts as (Settings), `active` is who the CURRENT chat is speaking as
  /// (the in-chat switcher). `active` is kept for older PWA builds that only
  /// know that key — additive-only, per the API contract.
  List<Map<String, dynamic>> personas() {
    final svc = _personas;
    if (svc == null) return const [];
    final activeId = svc.persona.id;
    final defaultId = svc.defaultPersonaId;
    return svc.personas
        .map(
          (p) => {
            'id': p.id,
            'label': p.displayLabel,
            'name': p.name,
            'active': p.id == activeId,
            'default': p.id == defaultId,
          },
        )
        .toList();
  }

  /// Change which persona NEW chats start as (Settings → Personas). Leaves the
  /// open chat alone. Returns false if personas aren't wired.
  Future<bool> setPersona(String id) async {
    final svc = _personas;
    if (svc == null) return false;
    await svc.setDefaultPersona(id);
    _notify();
    return true;
  }

  /// Speak as [id] in the CURRENT chat, and bind the session to it — the web
  /// counterpart of the desktop composer's persona switcher. Saves immediately
  /// so the binding survives a reload even if the user says nothing else.
  Future<bool> setChatPersona(String id) async {
    final svc = _personas;
    if (svc == null) return false;
    await svc.setActivePersona(id);
    await _chat.persistSessionPersona();
    _notify();
    return true;
  }

  /// Full persona detail for the editor (text + name/title), or null if absent.
  Map<String, dynamic>? personaDetail(String id) {
    final svc = _personas;
    if (svc == null) return null;
    for (final p in svc.personas) {
      if (p.id == id) {
        return {
          'id': p.id,
          'title': p.title,
          'name': p.name,
          'persona': p.persona,
          'birthday': p.birthday,
        };
      }
    }
    return null;
  }

  /// Create a new persona (and make it active, matching the desktop). Returns
  /// false if personas aren't wired.
  Future<bool> createPersona(Map<String, dynamic> f) async {
    final svc = _personas;
    if (svc == null) return false;
    await svc.createPersona(
      f['title']?.toString() ?? '',
      f['name']?.toString() ?? 'User',
      f['persona']?.toString() ?? '',
      null,
      birthday: f['birthday']?.toString() ?? '',
    );
    _notify();
    return true;
  }

  /// Edit an existing persona's text fields (only provided keys change).
  Future<bool> updatePersona(String id, Map<String, dynamic> f) async {
    final svc = _personas;
    if (svc == null) return false;
    UserPersona? existing;
    for (final p in svc.personas) {
      if (p.id == id) {
        existing = p;
        break;
      }
    }
    if (existing == null) return false;
    await svc.updatePersona(
      existing.copyWith(
        title: f.containsKey('title') ? f['title']?.toString() : null,
        name: f.containsKey('name') ? f['name']?.toString() : null,
        persona: f.containsKey('persona') ? f['persona']?.toString() : null,
        birthday: f.containsKey('birthday') ? f['birthday']?.toString() : null,
      ),
    );
    _notify();
    return true;
  }

  /// Delete a persona. The service refuses to delete the last one (throws),
  /// which we surface as false. Returns false if personas aren't wired.
  Future<bool> deletePersona(String id) async {
    final svc = _personas;
    if (svc == null) return false;
    try {
      await svc.deletePersona(id);
    } catch (_) {
      return false;
    }
    _notify();
    return true;
  }

  /// Where imported persona avatars are written — the same directory the
  /// desktop's persona page passes to [UserPersonaService.importFromJsonFile].
  /// Set by the host assembly; null until then (import still works, avatars
  /// from the file just aren't unpacked to disk).
  String? avatarSaveDir;

  /// Import a persona JSON document (the same formats the desktop's
  /// "Import from JSON" accepts: Front Porch bundle, SillyTavern V2/V1
  /// export, V2 character card). Returns the imported persona's name like
  /// the desktop's snackbar — or null on failure, where the desktop answers
  /// "Import failed — unrecognized format"; the route turns that into 400.
  Future<String?> importJson(String text) async {
    final svc = _personas;
    if (svc == null) return null;
    final file = File(
      '${Directory.systemTemp.path}/fpai_personas_import_${DateTime.now().microsecondsSinceEpoch}.json',
    );
    try {
      await file.writeAsString(text);
      final imported = await svc.importFromJsonFile(
        file.path,
        avatarSaveDir: avatarSaveDir,
      );
      _notify();
      return imported?.name;
    } finally {
      if (file.existsSync()) file.deleteSync();
    }
  }

  /// The persona's ST-format JSON export, in the same shape and with the
  /// same file name the desktop writes (`Ada_Lovelace_FPAIpersona.json`,
  /// one [UserPersona] per file). Null if the id is unknown or personas
  /// aren't wired.
  Future<({String filename, List<int> bytes})?> exportJson(String id) async {
    final svc = _personas;
    if (svc == null) return null;
    UserPersona? persona;
    for (final p in svc.personas) {
      if (p.id == id) persona = p;
    }
    if (persona == null) return null;
    final outPath =
        '${Directory.systemTemp.path}/fpai_personas_export_${DateTime.now().microsecondsSinceEpoch}.json';
    await svc.exportPersonasToSTFormat([id], outPath);
    final bytes = await File(outPath).readAsBytes();
    try {
      File(outPath).deleteSync();
    } catch (_) {}
    // Same name the desktop's export dialog builds (user_persona_page.dart).
    final filename =
        '${persona.name.replaceAll(RegExp(r'[^\w\s]'), '').replaceAll(' ', '_')}_FPAIpersona.json';
    return (filename: filename, bytes: bytes);
  }
}
