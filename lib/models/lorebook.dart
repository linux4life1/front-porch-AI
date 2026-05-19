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

class LorebookEntry {
  String name; // Display name for the entry
  String key; // Keywords to trigger this entry (comma-separated)
  String content; // The actual lore content
  bool enabled;
  bool isTriggered; // Runtime state for UI indication
  bool constant; // Always active if true
  int stickyDepth; // How many messages it stays active
  int remainingDepth; // Runtime counter

  LorebookEntry({
    this.name = '',
    required this.key,
    required this.content,
    this.enabled = true,
    this.isTriggered = false,
    this.constant = false,
    this.stickyDepth = 1,
    this.remainingDepth = 0,
  });

  /// Display label: name if available, otherwise key, otherwise 'Unnamed Entry'
  String get displayName {
    if (name.isNotEmpty) return name;
    if (key.isNotEmpty) return key;
    return 'Unnamed Entry';
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'key': key,
      'keys': key.split(',').map((k) => k.trim()).where((k) => k.isNotEmpty).toList(),
      'content': content,
      'enabled': enabled,
      'constant': constant,
      'sticky_depth': stickyDepth,
    };
  }

  factory LorebookEntry.fromJson(Map<String, dynamic> json) {
    // ── Extract keys ──────────────────────────────────────────────────────
    // Priority: keys[] > key[] > key(string) > secondary_keys[] > keysecondary[]
    // SillyTavern: key is array, keysecondary is array
    // Chub: key is array, keys is duplicate array, secondary_keys/keysecondary
    // Front Porch: key is comma-separated string
    final List<String> allKeys = [];

    // Primary keys
    if (json['keys'] != null) {
      _addKeysToList(json['keys'], allKeys);
    } else if (json['key'] != null) {
      _addKeysToList(json['key'], allKeys);
    }

    // Secondary keys (append to primary)
    if (json['secondary_keys'] != null) {
      _addKeysToList(json['secondary_keys'], allKeys);
    } else if (json['keysecondary'] != null) {
      _addKeysToList(json['keysecondary'], allKeys);
    }

    final String keyStr = allKeys.join(', ');

    // ── Extract name ──────────────────────────────────────────────────────
    // Chub: 'name' field
    // SillyTavern: 'comment' field
    // Front Porch: 'name' field
    final String name = json['name']?.toString() ??
        json['comment']?.toString() ??
        '';

    // ── Extract enabled state ─────────────────────────────────────────────
    // Chub: 'enabled' (true = enabled)
    // SillyTavern: 'disable' (true = disabled)
    // Front Porch: 'enabled'
    bool enabled = true;
    if (json['enabled'] != null) {
      enabled = json['enabled'] == true;
    } else if (json['disable'] != null) {
      enabled = json['disable'] != true;
    }

    // ── Extract constant ──────────────────────────────────────────────────
    final bool constant = json['constant'] == true;

    // ── Extract sticky depth ──────────────────────────────────────────────
    // Various field names across formats
    int stickyDepth = 1;
    if (json['sticky_depth'] is int) {
      stickyDepth = json['sticky_depth'] as int;
    } else if (json['insertion_order'] is int) {
      stickyDepth = json['insertion_order'] as int;
    } else if (json['depth'] is int) {
      stickyDepth = json['depth'] as int;
    } else if (json['sticky'] is int) {
      stickyDepth = json['sticky'] as int;
    }

    return LorebookEntry(
      name: name,
      key: keyStr,
      content: json['content']?.toString() ?? '',
      enabled: enabled,
      constant: constant,
      stickyDepth: stickyDepth > 0 ? stickyDepth : 1,
    );
  }

  /// Helper to add keys from various formats into a list.
  /// Handles: List of strings, single string, or comma-separated string.
  static void _addKeysToList(dynamic value, List<String> target) {
    if (value == null) return;

    if (value is List) {
      for (final item in value) {
        if (item != null) {
          final str = item.toString().trim();
          if (str.isNotEmpty) {
            target.add(str);
          }
        }
      }
    } else if (value is String) {
      // Could be comma-separated or a single key
      if (value.contains(',')) {
        for (final part in value.split(',')) {
          final trimmed = part.trim();
          if (trimmed.isNotEmpty) {
            target.add(trimmed);
          }
        }
      } else {
        final trimmed = value.trim();
        if (trimmed.isNotEmpty) {
          target.add(trimmed);
        }
      }
    }
  }
}

class Lorebook {
  List<LorebookEntry> entries;

  Lorebook({required this.entries});

  Map<String, dynamic> toJson() {
    return {
      'entries': entries.map((e) => e.toJson()).toList(),
    };
  }

  factory Lorebook.fromJson(Map<String, dynamic> json) {
    final dynamic entriesData = json['entries'];
    List<Map<String, dynamic>> entriesList = [];

    if (entriesData == null) {
      // No entries at all
      return Lorebook(entries: []);
    } else if (entriesData is List) {
      // Front Porch format: entries is a List
      entriesList = entriesData.whereType<Map<String, dynamic>>().toList();
    } else if (entriesData is Map) {
      // SillyTavern / Chub format: entries is a Map with string keys
      // e.g., {"0": {...}, "1": {...}} or {"1": {...}, "2": {...}}
      entriesList = entriesData.values
          .whereType<Map<String, dynamic>>()
          .toList();
    }

    final List<LorebookEntry> entries = entriesList
        .map((e) => LorebookEntry.fromJson(e))
        .toList();

    return Lorebook(entries: entries);
  }

  /// Parse a raw JSON object that may be in SillyTavern, Chub.ai, or Front Porch format.
  /// Returns a Map with 'name', 'description', and 'lorebook' keys suitable for World creation.
  static Map<String, dynamic> parseRawLorebookJson(Map<String, dynamic> json) {
    final String name = json['name']?.toString() ?? 'Imported Lorebook';
    final String description = json['description']?.toString() ?? '';

    return {
      'name': name,
      'description': description,
      'lorebook': Lorebook.fromJson(json).toJson(),
    };
  }
}
