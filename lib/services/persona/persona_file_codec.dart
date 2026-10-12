// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/services/persona/persona_ids.dart';
import 'package:front_porch_ai/services/persona/user_persona.dart';

/// Persona file formats: cloud-sync JSON, SillyTavern export, and the
/// import auto-detection. Pure transforms; persistence stays on the service.
class PersonaFileCodec {
  const PersonaFileCodec._();

  /// Cloud-sync payload: every persona plus the default id.
  static Map<String, dynamic> encodeCloud({
    required String defaultPersonaId,
    required List<UserPersona> personas,
  }) => {
    'active_persona_id': defaultPersonaId,
    'personas': personas.map((p) => p.toJson()).toList(),
  };

  /// SillyTavern-compliant export of [selected].
  static Map<String, dynamic> encodeSillyTavern(List<UserPersona> selected) {
    final Map<String, String> personasMap = {};
    final Map<String, dynamic> descriptionsMap = {};

    for (final p in selected) {
      String key = p.avatarPath != null
          ? p.avatarPath!.split('/').last
          : '${p.name.replaceAll(RegExp(r'[^\w\s]'), '').replaceAll(' ', '_')}.png';

      if (personasMap.containsKey(key)) {
        key = '${p.id}_$key';
      }

      personasMap[key] = p.name;
      descriptionsMap[key] = {'description': p.persona, 'title': p.title};
    }

    return {'personas': personasMap, 'persona_descriptions': descriptionsMap};
  }

  /// Personas to import from [json], auto-detecting the format:
  /// - **SillyTavern export**: `{ personas: {filename: name}, persona_descriptions: {filename: {description, title, ...}} }`
  /// - **Front Porch native**: `{ personas: [...] }` — array of persona objects
  /// - **TavernAI V2 / Backyard AI**: character card JSON with `name`,
  ///   `description`, `personality`, `user_persona`, etc.
  /// - **Generic**: any JSON with at least `name` + `description`
  ///
  /// Each decoded persona goes to [add] as soon as it is read, so a bad
  /// entry part-way through a batch keeps the ones before it.
  ///
  /// [avatarSaveDir] is where decoded base64 avatars are saved; when null,
  /// base64 avatars are discarded. Returns the first persona, or null for an
  /// unrecognized or empty payload.
  static Future<UserPersona?> importAll(
    Map<String, dynamic> json, {
    required Future<void> Function(UserPersona persona) add,
    String? avatarSaveDir,
  }) async {
    // ── SillyTavern export format ──
    if (json.containsKey('personas') &&
        json['personas'] is Map &&
        json.containsKey('persona_descriptions') &&
        json['persona_descriptions'] is Map) {
      debugPrint('[Persona:Import] Detected SillyTavern export format');
      final personasMap = json['personas'] as Map<String, dynamic>;
      final descriptionsMap =
          json['persona_descriptions'] as Map<String, dynamic>;

      UserPersona? first;
      for (final entry in personasMap.entries) {
        final avatarKey = entry.key; // e.g. "1766044822296-Linus.png"
        final name = entry.value as String? ?? 'Imported Persona';
        final descEntry = descriptionsMap[avatarKey] as Map<String, dynamic>?;
        // ST uses 'description' as the persona text.
        final personaText = descEntry?['description'] as String? ?? '';
        final title = descEntry?['title'] as String? ?? '';
        final persona = UserPersona(
          id: newPersonaId(),
          title: title,
          name: name,
          persona: personaText,
          avatarPath: null,
        );
        await add(persona);
        first ??= persona;
      }
      if (first != null) {
        debugPrint(
          '[Persona:Import] Imported ${personasMap.length} persona(s) from SillyTavern',
        );
      }
      return first;
    }

    // ── Front Porch native batch format (personas is a List) ──
    if (json.containsKey('personas') && json['personas'] is List) {
      final list = (json['personas'] as List)
          .map((e) => UserPersona.fromJson(e as Map<String, dynamic>))
          .toList();
      if (list.isEmpty) return null;
      for (final persona in list) {
        await add(persona);
      }
      debugPrint(
        '[Persona:Import] Imported ${list.length} persona(s) from Front Porch native format',
      );
      return list.first;
    }

    final single = await _decodeSingle(json, avatarSaveDir: avatarSaveDir);
    if (single != null) await add(single);
    return single;
  }

  static Future<UserPersona?> _decodeSingle(
    Map<String, dynamic> json, {
    String? avatarSaveDir,
  }) async {
    String name = '';
    String title = '';
    String personaText = '';
    String? avatarPath;

    // TavernAI V2 / Backyard AI character card
    if (json.containsKey('first_mes') ||
        json.containsKey('mes_example') ||
        json.containsKey('personality') ||
        json.containsKey('scenario')) {
      name = json['name'] as String? ?? '';
      personaText =
          json['user_persona'] as String? ??
          json['description'] as String? ??
          '';
      title = json['creator_notes'] as String? ?? '';
      debugPrint('[Persona:Import] Detected TavernAI V2 / Backyard AI format');
    }
    // Simple object with name + description
    else if (json.containsKey('name') && json.containsKey('description')) {
      name = json['name'] as String? ?? '';
      personaText =
          json['persona'] as String? ?? json['description'] as String? ?? '';
      title = json['title'] as String? ?? '';

      final avatarData = json['avatar'] as String?;
      if (avatarData != null &&
          avatarData.length > 200 &&
          avatarSaveDir != null) {
        avatarPath = await decodeBase64Avatar(avatarData, name, avatarSaveDir);
      } else if (avatarData != null && avatarData.length <= 200) {
        avatarPath = avatarData;
      }
      debugPrint('[Persona:Import] Detected generic name+description format');
    }
    // Minimal fallback
    else if (json.containsKey('name')) {
      name = json['name'] as String? ?? 'Imported Persona';
      personaText =
          json['persona'] as String? ??
          json['description'] as String? ??
          json['bio'] as String? ??
          '';
      debugPrint('[Persona:Import] Detected minimal format');
    } else {
      debugPrint(
        '[Persona:Import] Unrecognized format — no parseable keys found',
      );
      return null;
    }

    if (name.isEmpty) name = 'Imported Persona';

    return UserPersona(
      id: newPersonaId(),
      title: title,
      name: name,
      persona: personaText,
      avatarPath: avatarPath,
    );
  }

  /// Decode a base64-encoded avatar string and save it under [saveDir].
  /// Returns the saved file path, or null on failure.
  static Future<String?> decodeBase64Avatar(
    String base64Data,
    String personaName,
    String saveDir,
  ) async {
    try {
      // Strip data URI prefix if present (e.g. "data:image/png;base64,...")
      String raw = base64Data;
      String ext = '.png';
      if (raw.startsWith('data:')) {
        final comma = raw.indexOf(',');
        if (comma != -1) {
          final header = raw.substring(0, comma);
          raw = raw.substring(comma + 1);
          if (header.contains('jpeg') || header.contains('jpg')) ext = '.jpg';
          if (header.contains('webp')) ext = '.webp';
        }
      }

      final bytes = base64Decode(raw);
      final safeName = personaName.replaceAll(RegExp(r'[^\w]'), '_');
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'persona_${safeName}_$timestamp$ext';
      final dir = Directory(saveDir);
      await dir.create(recursive: true);
      final filePath = '${dir.path}/$fileName';
      await File(filePath).writeAsBytes(bytes);
      debugPrint('[Persona:Import] Saved avatar to $filePath');
      return filePath;
    } catch (e) {
      debugPrint('[Persona:Import] Failed to decode base64 avatar: $e');
      return null;
    }
  }
}
