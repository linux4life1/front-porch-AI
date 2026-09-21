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

part of 'user_persona_service.dart';

/// File import/export. CRUD stays on [UserPersonaService].
extension UserPersonaServiceImport on UserPersonaService {
  // ── Cloud Sync helpers ──────────────────────────────────────────────

  /// Export all personas + active ID to a JSON file for cloud sync.
  Future<void> _exportToFileImpl(String filePath) async {
    final data = {
      'active_persona_id': _defaultPersonaId,
      'personas': _personas.map((p) => p.toJson()).toList(),
    };
    final file = File(filePath);
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(data));
  }

  /// Import personas from a JSON file (downloaded from cloud).
  Future<void> _importFromFileImpl(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) return;
    final content = await file.readAsString();
    final data = jsonDecode(content) as Map<String, dynamic>;
    final list = (data['personas'] as List?)
        ?.map((e) => UserPersona.fromJson(e))
        .toList();
    if (list != null && list.isNotEmpty) {
      // Clear existing personas from DB and re-import
      for (final p in _personas) {
        await _db.deletePersonaById(p.id);
      }
      _personas = list;
      _defaultPersonaId = data['active_persona_id'] ?? _personas.first.id;
      _activePersonaId = _defaultPersonaId;

      for (final p in _personas) {
        await _db.insertPersona(
          PersonasCompanion.insert(
            id: p.id,
            title: Value(p.title),
            name: Value(p.name),
            persona: Value(p.persona),
            avatarPath: Value(p.avatarPath),
            birthday: Value(p.birthday.isEmpty ? null : p.birthday),
            isActive: Value(p.id == _defaultPersonaId),
          ),
        );
      }
      notify();
    }
  }

  /// Import persona(s) from a JSON file.
  ///
  /// Supports multiple formats with auto-detection:
  /// - **SillyTavern export**: `{ personas: {filename: name}, persona_descriptions: {filename: {description, title, ...}} }`
  /// - **Front Porch native**: `{ personas: [...] }` — array of persona objects
  /// - **TavernAI V2 / Backyard AI**: character card JSON with `name`, `description`,
  ///   `personality`, `user_persona`, etc.
  /// - **Generic**: any JSON with at least `name` + `description`
  ///
  /// [avatarSaveDir] is the directory where decoded base64 avatars will be saved.
  /// If null, base64 avatars are discarded.
  ///
  /// Returns the first imported [UserPersona], or null on failure.
  Future<UserPersona?> _importFromJsonFileImpl(
    String filePath, {
    String? avatarSaveDir,
  }) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        debugPrint('[Persona:Import] File not found: $filePath');
        return null;
      }
      final content = await file.readAsString();
      final data = jsonDecode(content);

      if (data is! Map<String, dynamic>) {
        debugPrint(
          '[Persona:Import] Unexpected JSON root type: ${data.runtimeType}',
        );
        return null;
      }
      final json = data;

      // ── SillyTavern export format ──
      // { personas: {filename: name}, persona_descriptions: {filename: {description, ...}} }
      if (json.containsKey('personas') &&
          json['personas'] is Map &&
          json.containsKey('persona_descriptions') &&
          json['persona_descriptions'] is Map) {
        debugPrint('[Persona:Import] Detected SillyTavern export format');
        final personasMap = json['personas'] as Map<String, dynamic>;
        final descriptionsMap =
            json['persona_descriptions'] as Map<String, dynamic>;

        UserPersona? firstImported;
        for (final entry in personasMap.entries) {
          final avatarKey = entry.key; // e.g. "1766044822296-Linus.png"
          final name = entry.value as String? ?? 'Imported Persona';

          // Look up the description entry for this avatar key
          final descEntry = descriptionsMap[avatarKey] as Map<String, dynamic>?;
          final personaText =
              descEntry?['description'] as String? ??
              ''; // ST uses 'description' as the persona text
          final title = descEntry?['title'] as String? ?? '';

          final newPersona = UserPersona(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            title: title,
            name: name,
            persona: personaText,
            avatarPath: null,
          );

          await _addImportedPersona(newPersona);
          firstImported ??= newPersona;

          // Small delay to ensure unique IDs
          await Future.delayed(const Duration(milliseconds: 2));
        }

        if (firstImported != null) {
          debugPrint(
            '[Persona:Import] Imported ${personasMap.length} persona(s) from SillyTavern',
          );
        }
        return firstImported;
      }

      // ── Front Porch native batch format (personas is a List) ──
      if (json.containsKey('personas') && json['personas'] is List) {
        final list = (json['personas'] as List)
            .map((e) => UserPersona.fromJson(e as Map<String, dynamic>))
            .toList();
        if (list.isNotEmpty) {
          for (final p in list) {
            await _addImportedPersona(p);
          }
          debugPrint(
            '[Persona:Import] Imported ${list.length} persona(s) from Front Porch native format',
          );
          return list.first;
        }
        return null;
      }

      // ── Single object formats ──

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
        debugPrint(
          '[Persona:Import] Detected TavernAI V2 / Backyard AI format',
        );
      }
      // Simple object with name + description
      else if (json.containsKey('name') && json.containsKey('description')) {
        name = json['name'] as String? ?? '';
        personaText =
            json['persona'] as String? ?? json['description'] as String? ?? '';
        title = json['title'] as String? ?? '';

        // Handle base64 avatar
        final avatarData = json['avatar'] as String?;
        if (avatarData != null &&
            avatarData.length > 200 &&
            avatarSaveDir != null) {
          avatarPath = await _decodeBase64Avatar(
            avatarData,
            name,
            avatarSaveDir,
          );
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

      final newPersona = UserPersona(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: title,
        name: name,
        persona: personaText,
        avatarPath: avatarPath,
      );

      await _addImportedPersona(newPersona);
      return newPersona;
    } catch (e) {
      debugPrint('[Persona:Import] Error importing persona JSON: $e');
      return null;
    }
  }

  /// Internal helper — persist an imported persona to DB and memory.
  Future<void> _addImportedPersona(UserPersona p) async {
    // Prevent duplicate IDs
    final existingIds = _personas.map((e) => e.id).toSet();
    UserPersona toInsert = p;
    if (existingIds.contains(p.id)) {
      toInsert = p.copyWith(title: p.title, name: p.name, persona: p.persona);
      // Generate new ID since copyWith preserves original
      toInsert = UserPersona(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: p.title,
        name: p.name,
        persona: p.persona,
        avatarPath: p.avatarPath,
        birthday: p.birthday,
      );
    }

    await _db.insertPersona(
      PersonasCompanion.insert(
        id: toInsert.id,
        title: Value(toInsert.title),
        name: Value(toInsert.name),
        persona: Value(toInsert.persona),
        avatarPath: Value(toInsert.avatarPath),
        birthday: Value(toInsert.birthday.isEmpty ? null : toInsert.birthday),
        isActive: const Value(true),
      ),
    );

    // Set as default + current (same reasoning as createPersona).
    await _db.setActivePersona(toInsert.id);
    _personas.add(toInsert);
    _defaultPersonaId = toInsert.id;
    _activePersonaId = toInsert.id;
    notify();
  }

  /// Decode a base64-encoded avatar string and save it to disk.
  /// Returns the saved file path, or null on failure.
  Future<String?> _decodeBase64Avatar(
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

  /// Export multiple personas to a JSON file in SillyTavern compliant format.
  Future<void> _exportPersonasToSTFormatImpl(
    List<String> personaIds,
    String filePath,
  ) async {
    final Map<String, String> personasMap = {};
    final Map<String, dynamic> descriptionsMap = {};

    for (final id in personaIds) {
      final p = _personas.firstWhere((e) => e.id == id, orElse: () => persona);

      String key = p.avatarPath != null
          ? p.avatarPath!.split('/').last
          : '${p.name.replaceAll(RegExp(r'[^\w\s]'), '').replaceAll(' ', '_')}.png';

      if (personasMap.containsKey(key)) {
        key = '${p.id}_$key';
      }

      personasMap[key] = p.name;
      descriptionsMap[key] = {'description': p.persona, 'title': p.title};
    }

    final data = {
      'personas': personasMap,
      'persona_descriptions': descriptionsMap,
    };

    final file = File(filePath);
    await file.parent.create(recursive: true);
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(data));
  }
}
