// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Card completeness checklist for Stoop uploads. Mirrors
// backporch-server/src/lib/card-completeness.ts and site/src/stoop/completeness.js
// so the app, hub, and API reject the same incomplete shells (empty first
// message / persona / scenario; worlds need climate; lorebook is optional).

/// One field on the completeness checklist.
class StoopFieldStatus {
  final String key;
  final String label;
  final bool present;
  final int chars;
  final bool critical;

  const StoopFieldStatus({
    required this.key,
    required this.label,
    required this.present,
    required this.chars,
    required this.critical,
  });
}

/// Result of [StoopCardCompleteness.assess].
class StoopCompleteness {
  final bool incomplete;
  final List<String> missingCritical;
  final List<String> missingOptional;
  final List<StoopFieldStatus> fields;
  final String? cardName;
  final List<String> notes;

  const StoopCompleteness({
    required this.incomplete,
    required this.missingCritical,
    required this.missingOptional,
    required this.fields,
    required this.cardName,
    required this.notes,
  });

  /// Short user-facing error for snackbars / wizard banners.
  String get message {
    if (!incomplete) return '';
    final miss = missingCritical.join(', ');
    return 'This card is incomplete for The Stoop. Missing: $miss. '
        'Fill those fields in the character editor, then try again.';
  }
}

/// Pure completeness assessor for Stoop upload payloads (`type` + card JSON).
class StoopCardCompleteness {
  StoopCardCompleteness._();

  static bool _present(dynamic v) {
    if (v is String) return v.trim().isNotEmpty;
    if (v is List) {
      return v.any((item) {
        if (item is String) return item.trim().isNotEmpty;
        return item != null;
      });
    }
    return false;
  }

  static String _str(dynamic v) => v is String ? v : '';

  static int _chars(dynamic v) {
    if (v is String) return v.trim().length;
    if (v is List) {
      var n = 0;
      for (final item in v) {
        if (item is String) n += item.trim().length;
      }
      return n;
    }
    return 0;
  }

  static Map<String, dynamic> unwrapCard(Map<String, dynamic>? cardJson) {
    if (cardJson == null) return <String, dynamic>{};
    final data = cardJson['data'];
    if (data is Map) {
      final d = Map<String, dynamic>.from(data);
      if (_present(d['first_mes']) ||
          _present(d['description']) ||
          _present(d['personality']) ||
          _present(d['system_prompt'])) {
        return {...cardJson, ...d, 'extensions': d['extensions'] ?? cardJson['extensions']};
      }
    }
    return cardJson;
  }

  static StoopFieldStatus _field(
    String key,
    String label,
    dynamic value, {
    required bool critical,
  }) {
    return StoopFieldStatus(
      key: key,
      label: label,
      present: _present(value),
      chars: _chars(value),
      critical: critical,
    );
  }

  static ({int entries, int filled, int placeholder, int totalChars}) _lorebook(
    dynamic book,
  ) {
    if (book is! Map) {
      return (entries: 0, filled: 0, placeholder: 0, totalChars: 0);
    }
    final entries = book['entries'];
    if (entries is! List) {
      return (entries: 0, filled: 0, placeholder: 0, totalChars: 0);
    }
    var filled = 0;
    var placeholder = 0;
    var totalChars = 0;
    for (final e in entries) {
      if (e is! Map) continue;
      final content = _str(e['content']).trim();
      totalChars += content.length;
      if (content.isEmpty) {
        placeholder += 1;
        continue;
      }
      if (RegExp(r'\[Insert\b', caseSensitive: false).hasMatch(content)) {
        placeholder += 1;
      } else {
        filled += 1;
      }
    }
    return (
      entries: entries.length,
      filled: filled,
      placeholder: placeholder,
      totalChars: totalChars,
    );
  }

  static StoopCompleteness assess(Map<String, dynamic>? cardJson, String type) {
    final card = unwrapCard(cardJson);
    switch (type.toUpperCase()) {
      case 'GROUP':
        return _group(card);
      case 'WORLD':
        return _world(card);
      default:
        return _solo(card);
    }
  }

  static StoopCompleteness _solo(Map<String, dynamic> card) {
    final first = card['first_mes'] ?? card['first_message'];
    final fields = <StoopFieldStatus>[
      _field('first_mes', 'First message', first, critical: true),
      _field('description', 'Description', card['description'], critical: true),
      _field('personality', 'Personality', card['personality'], critical: true),
      _field('scenario', 'Scenario', card['scenario'], critical: true),
      _field('mes_example', 'Example messages', card['mes_example'], critical: false),
      _field('system_prompt', 'System prompt', card['system_prompt'], critical: false),
      _field(
        'post_history_instructions',
        'Post-history instructions',
        card['post_history_instructions'],
        critical: false,
      ),
      _field('creator_notes', 'Creator notes', card['creator_notes'], critical: false),
      _field(
        'alternate_greetings',
        'Alternate greetings',
        card['alternate_greetings'],
        critical: false,
      ),
    ];

    final hasIdentity =
        _present(card['description']) || _present(card['personality']);
    final hasFirst = _present(first);
    final hasScenario = _present(card['scenario']);
    final missingCritical = <String>[];
    if (!hasFirst) missingCritical.add('First message');
    if (!hasIdentity) missingCritical.add('Description or personality');
    if (!hasScenario) missingCritical.add('Scenario');

    final notes = <String>[];
    final book = _lorebook(card['character_book'] ?? card['lorebook']);
    if (book.entries > 0) {
      notes.add(
        'Lorebook: ${book.filled}/${book.entries} filled'
        '${book.placeholder > 0 ? ' · ${book.placeholder} empty/placeholder' : ''}',
      );
    }
    if (!hasFirst &&
        !hasIdentity &&
        _present(card['system_prompt']) &&
        _chars(card['system_prompt']) > 500) {
      notes.add(
        'Looks like a template/shell: system prompt present, character fields empty',
      );
    }

    final name = _str(card['name']).trim();
    return StoopCompleteness(
      incomplete: missingCritical.isNotEmpty,
      missingCritical: missingCritical,
      missingOptional: fields
          .where((f) => !f.critical && !f.present)
          .map((f) => f.label)
          .toList(),
      fields: fields,
      cardName: name.isEmpty ? null : name,
      notes: notes,
    );
  }

  static StoopCompleteness _group(Map<String, dynamic> card) {
    final members = (card['members'] is List)
        ? card['members'] as List
        : (card['raw_member_data'] is List)
            ? card['raw_member_data'] as List
            : const [];
    final first = card['first_mes'] ?? card['first_message'];
    final fields = <StoopFieldStatus>[
      _field('first_mes', 'Group first message', first, critical: true),
      _field('scenario', 'Group scenario', card['scenario'], critical: true),
      _field('system_prompt', 'System prompt', card['system_prompt'], critical: false),
    ];
    final missingCritical = <String>[];
    if (!_present(first)) missingCritical.add('Group first message');
    if (!_present(card['scenario'])) missingCritical.add('Group scenario');
    if (members.isEmpty) missingCritical.add('Members');

    for (var i = 0; i < members.length; i++) {
      final raw = members[i];
      final m = raw is Map
          ? Map<String, dynamic>.from(raw)
          : <String, dynamic>{};
      final label = _str(m['name']).trim().isEmpty
          ? 'Member ${i + 1}'
          : _str(m['name']).trim();
      final idOk = _present(m['description']) || _present(m['personality']);
      fields.add(_field('member_${i}_name', '$label · name', m['name'], critical: true));
      fields.add(
        _field(
          'member_${i}_identity',
          '$label · description/personality',
          idOk ? 'ok' : '',
          critical: true,
        ),
      );
      if (_str(m['name']).trim().isEmpty) missingCritical.add('$label: name');
      if (!idOk) {
        missingCritical.add('$label: description or personality');
      }
    }

    return StoopCompleteness(
      incomplete: missingCritical.toSet().isNotEmpty,
      missingCritical: missingCritical.toSet().toList(),
      missingOptional: fields
          .where((f) => !f.critical && !f.present)
          .map((f) => f.label)
          .toList(),
      fields: fields,
      cardName: _str(card['name']).trim().isEmpty ? null : _str(card['name']).trim(),
      notes: ['${members.length} member(s)'],
    );
  }

  static StoopCompleteness _world(Map<String, dynamic> card) {
    final biomeRaw = card['biome'];
    final biome = biomeRaw is Map
        ? Map<String, dynamic>.from(biomeRaw)
        : <String, dynamic>{};
    final book = _lorebook(card['lorebook']);
    final climatePresent = _present(biome['displayName']) ||
        _present(biome['description']) ||
        _present(biome['feel']);
    final fields = <StoopFieldStatus>[
      _field('biome', 'Biome / climate', climatePresent ? 'ok' : '', critical: true),
      // Lore is useful but optional — worlds can ship climate first.
      _field(
        'lorebook',
        'Lorebook content',
        book.totalChars > 0 ? 'ok' : '',
        critical: false,
      ),
    ];
    final missingCritical = <String>[];
    if (!climatePresent) missingCritical.add('Biome / climate');

    return StoopCompleteness(
      incomplete: missingCritical.isNotEmpty,
      missingCritical: missingCritical,
      missingOptional: fields
          .where((f) => !f.critical && !f.present)
          .map((f) => f.label)
          .toList(),
      fields: fields,
      cardName: _str(card['name']).trim().isEmpty ? null : _str(card['name']).trim(),
      notes: [
        'Lorebook: ${book.filled}/${book.entries} filled'
        '${book.placeholder > 0 ? ' · ${book.placeholder} empty/placeholder' : ''}'
        '${book.entries == 0 ? ' (optional)' : ''}',
      ],
    );
  }
}
