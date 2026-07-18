// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:math';

import 'package:intl/intl.dart';

/// Context passed to every macro resolver function.
///
/// Only [userName]/[characterName] are universal. The chat-context fields
/// (card fields, group roster, last messages, idle time) and the variable
/// store callbacks are supplied by ChatService's prompt build; contexts that
/// don't provide them (Stoop previews, image prompts) leave the dependent
/// macros untouched (pass-through), never silently blank.
class MacroContext {
  final String? userName;
  final String? characterName;
  final String? chatId;
  final String? characterId;

  // Card fields of the speaking character ('' is valid; null = unavailable).
  final String? description;
  final String? personality;
  final String? scenario;

  /// The user persona's description text.
  final String? userPersona;

  /// All group member names (group mode); null in 1:1 / non-chat contexts.
  final List<String>? groupMemberNames;

  final String? lastMessage;
  final String? lastUserMessage;
  final String? lastCharMessage;

  /// Time since the user's last message (in-memory clock; null after a
  /// restart or outside chat).
  final Duration? idleDuration;

  // Variable store — local = per-chat (persisted with the session),
  // global = app-wide. Null callbacks leave var macros untouched.
  final String? Function(String name)? getLocalVar;
  final void Function(String name, String value)? setLocalVar;
  final String? Function(String name)? getGlobalVar;
  final void Function(String name, String value)? setGlobalVar;

  const MacroContext({
    this.userName,
    this.characterName,
    this.chatId,
    this.characterId,
    this.description,
    this.personality,
    this.scenario,
    this.userPersona,
    this.groupMemberNames,
    this.lastMessage,
    this.lastUserMessage,
    this.lastCharMessage,
    this.idleDuration,
    this.getLocalVar,
    this.setLocalVar,
    this.getGlobalVar,
    this.setGlobalVar,
  });
}

/// Internal registry entry.
class _MacroEntry {
  final String name;
  final String Function(List<String> args, MacroContext ctx) fn;
  const _MacroEntry({required this.name, required this.fn});
}

/// Central macro engine. Has a name → resolver registry.
/// Replace all known `{{...}}` patterns in text via [resolve].
/// Unknown macros pass through unchanged.
class MacroResolver {
  final Map<String, _MacroEntry> _registry = {};
  bool _defaultsRegistered = false;
  int _pickCounter = 0;

  static final _commentPattern = RegExp(r'\{\{//.*?\}\}');
  static final _escapePattern = RegExp(r'\\\{\{');
  // Accepts both ST separator styles: {{name::a::b}} and {{name:a,b}}.
  static final _macroPattern = RegExp(r'\{\{(\w+)(?:(::?)(.+?))?\}\}');
  // Dedicated roll pass: ST allows {{roll:d6}}, {{roll::1d20+5}}, {{roll d20}}.
  static final _rollMacroPattern =
      RegExp(r'\{\{roll[\s:]+([^}]+)\}\}', caseSensitive: false);
  static final _rollPattern = RegExp(r'^(\d+)d(\d+)([+-]\d+)?$');
  // Legacy ST {{time_UTC±N}} form (the modern {{time::UTC±N}} rides the
  // generic pattern; this one's +N suffix does not).
  static final _timeUtcPattern =
      RegExp(r'\{\{time_UTC([+-]\d+)\}\}', caseSensitive: false);
  // {{trim}} eats surrounding whitespace/newlines — applied after the macro
  // pass so macros around it resolve first.
  static final _trimPattern = RegExp(
    r'[ \t]*\n?[ \t]*\{\{trim\}\}[ \t]*\n?[ \t]*',
    caseSensitive: false,
  );
  // Comma not preceded by a backslash (the \, escape ST supports in lists).
  static final _unescapedComma = RegExp(r'(?<!\\),');
  static final _rng = Random();

  MacroResolver() {
    _ensureDefaults();
  }

  void _ensureDefaults() {
    if (_defaultsRegistered) return;
    _defaultsRegistered = true;

    register('user', (args, ctx) => ctx.userName ?? '');
    register('char', (args, ctx) => ctx.characterName ?? '');
    // ({{words}} was removed with the old summary-prompt feature — the
    // Journal recap has a fixed length instruction.)

    // Phase 2 P0
    register('newline', (args, ctx) {
      final n = args.isNotEmpty ? int.tryParse(args[0]) ?? 1 : 1;
      return '\n' * n.clamp(1, 100);
    });
    register('space', (args, ctx) {
      final n = args.isNotEmpty ? int.tryParse(args[0]) ?? 1 : 1;
      return ' ' * n.clamp(1, 100);
    });
    register('noop', (args, ctx) => '');
    register('random', (args, ctx) {
      if (args.isEmpty) return '';
      return args[_rng.nextInt(args.length)];
    });
    // roll handled in resolve() for pass-through of invalid notation
    register('time', (args, ctx) {
      // {{time}} or {{time::UTC±N}} (ST timezone form).
      if (args.isNotEmpty) {
        final m = RegExp(r'^UTC([+-]\d+)$', caseSensitive: false)
            .firstMatch(args[0].trim());
        if (m != null) {
          final offset = int.tryParse(m.group(1)!) ?? 0;
          return DateFormat('HH:mm')
              .format(DateTime.now().toUtc().add(Duration(hours: offset)));
        }
      }
      return DateFormat('HH:mm').format(DateTime.now());
    });
    register('reverse', (args, ctx) {
      final text = args.join('::');
      return String.fromCharCodes(text.runes.toList().reversed);
    });
    // Partial support: ST adds the word to the banned-words sampler list;
    // we strip it from the prompt so the model never sees the directive.
    register('banned', (args, ctx) => '');
    register('datetimeformat', (args, ctx) {
      if (args.isEmpty) return '';
      final fmt = _momentToIcu(args.join('::'));
      try {
        return DateFormat(fmt).format(DateTime.now());
      } catch (_) {
        return '';
      }
    });
    register('timediff', (args, ctx) {
      if (args.length < 2) return '';
      final a = DateTime.tryParse(args[0].trim());
      final b = DateTime.tryParse(args[1].trim());
      if (a == null || b == null) return '';
      return _humanizeDuration(a.difference(b).abs());
    });
    register('date', (args, ctx) => DateFormat('yyyy-MM-dd').format(DateTime.now()));
    register('weekday', (args, ctx) => DateFormat('EEEE').format(DateTime.now()));
    register('isotime', (args, ctx) {
      final iso = DateTime.now().toIso8601String();
      return iso.split('T')[1].split('.').first;
    });
    register('isodate', (args, ctx) {
      return DateTime.now().toIso8601String().split('T')[0];
    });
  }

  void register(
    String name,
    String Function(List<String> args, MacroContext ctx) fn,
  ) {
    _registry[name.toLowerCase()] = _MacroEntry(name: name, fn: fn);
  }

  /// Replaces all known `{{...}}` macros and legacy `<user>`/`<char>` syntax.
  /// Unknown macros pass through unchanged.
  /// Returns empty string for null/empty input.
  /// [section] differentiates [{{pick}}] seeding across prompt sections
  /// (e.g. systemPrompt vs scenario) so the same position in different
  /// sections produces a different result.
  String resolve(String text, MacroContext context, {String section = ''}) {
    if (text.isEmpty) return text;

    _pickCounter = 0;
    var result = text;

    // 1. Escape: \{{ → sentinel (null byte)
    result = result.replaceAll(_escapePattern, '\x00');

    // 2. Strip {{// ...}} comments
    result = result.replaceAll(_commentPattern, '');

    // 3. Legacy angle-bracket syntax (case-insensitive)
    final charName = context.characterName ?? '';
    final userName = context.userName ?? '';
    result = result.replaceAll(
      RegExp(r'<char>', caseSensitive: false),
      charName,
    );
    result = result.replaceAll(
      RegExp(r'<user>', caseSensitive: false),
      userName,
    );

    // 4. {{roll ...}} first — its arg can contain spaces/colons the generic
    // pattern rejects. Handles :, ::, and space separators plus the ST
    // shorthands d6 → 1d6 and 6 → 1d6. Invalid formulas pass through.
    result = result.replaceAllMapped(_rollMacroPattern, (m) {
      var formula = m.group(1)!.trim().toLowerCase();
      if (RegExp(r'^\d+$').hasMatch(formula)) formula = '1d$formula';
      if (formula.startsWith('d')) formula = '1$formula';
      final rm = _rollPattern.firstMatch(formula);
      if (rm == null) return m.group(0)!;
      final count = int.parse(rm.group(1)!);
      final sides = int.parse(rm.group(2)!);
      final mod = int.tryParse(rm.group(3) ?? '') ?? 0;
      if (sides < 1 || count < 1 || count > 1000) return m.group(0)!;
      var total = 0;
      for (var i = 0; i < count; i++) {
        total += _rng.nextInt(sides) + 1;
      }
      return (total + mod).toString();
    });

    // 5. {{macro}} syntax via regex — walk all matches
    result = result.replaceAllMapped(_macroPattern, (m) {
      final name = m.group(1)!.toLowerCase();
      final sep = m.group(2);
      final argsStr = m.group(3);
      final args = _splitArgs(name, sep, argsStr);

      if (name == 'pick') {
        // Deterministic per chatId + characterId + position
        final seedKey = '${context.chatId}_${context.characterId}_${section}_$_pickCounter';
        _pickCounter++;
        final h = seedKey.hashCode.abs();
        return args.isEmpty ? '' : args[h % args.length];
      }

      final varResult = _varMacro(name, args, context);
      if (varResult != null) return varResult;

      final ctxResult = _contextMacro(name, context);
      if (ctxResult != null) return ctxResult;

      final entry = _registry[name];
      if (entry != null) return entry.fn(args, context);
      return m.group(0)!; // unknown macro → pass through
    });

    // 6. Legacy {{time_UTC±N}} + {{trim}} post-passes
    result = result.replaceAllMapped(_timeUtcPattern, (m) {
      final offset = int.tryParse(m.group(1)!) ?? 0;
      return DateFormat('HH:mm')
          .format(DateTime.now().toUtc().add(Duration(hours: offset)));
    });
    result = result.replaceAll(_trimPattern, '');

    // 7. Unescape sentinel back to {{
    result = result.replaceAll('\x00', '{{');

    return result;
  }

  /// ST chat-variable macros. Returns null when [name] is not a var macro OR
  /// the context has no store (→ pass through, visible rather than silent).
  /// Accepts both `{{setvar::k::v}}` and `{{setvar:k:v}}` (single-colon args
  /// arrive as one string and are split at the first colon).
  String? _varMacro(String name, List<String> args, MacroContext ctx) {
    final isGlobal = name.startsWith('setglobal') ||
        name.startsWith('getglobal') ||
        name.startsWith('addglobal') ||
        name.startsWith('incglobal') ||
        name.startsWith('decglobal');
    final op = isGlobal ? name.replaceFirst('global', '') : name;
    if (!{'setvar', 'getvar', 'addvar', 'incvar', 'decvar'}.contains(op)) {
      return null;
    }

    final get = isGlobal ? ctx.getGlobalVar : ctx.getLocalVar;
    final set = isGlobal ? ctx.setGlobalVar : ctx.setLocalVar;
    if (get == null || set == null || args.isEmpty) return null;

    String key = args[0];
    String value = args.length > 1 ? args.sublist(1).join('::') : '';
    if (args.length == 1 && key.contains(':') && op != 'getvar' &&
        op != 'incvar' && op != 'decvar') {
      final i = key.indexOf(':');
      value = key.substring(i + 1);
      key = key.substring(0, i);
    }
    key = key.trim();
    if (key.isEmpty) return null;

    switch (op) {
      case 'setvar':
        set(key, value);
        return '';
      case 'getvar':
        return get(key) ?? '';
      case 'addvar':
        final current = get(key) ?? '';
        final a = num.tryParse(current);
        final b = num.tryParse(value);
        set(key, a != null && b != null ? _numStr(a + b) : '$current$value');
        return '';
      case 'incvar':
      case 'decvar':
        final current = num.tryParse(get(key) ?? '') ?? 0;
        final next = op == 'incvar' ? current + 1 : current - 1;
        set(key, _numStr(next));
        return _numStr(next);
    }
    return null;
  }

  static String _numStr(num n) =>
      n == n.truncate() ? n.truncate().toString() : n.toString();

  /// Chat-context macros. Returns the substitution, or null when [name]
  /// isn't one of them or its data is unavailable (→ pass through).
  String? _contextMacro(String name, MacroContext ctx) {
    switch (name) {
      case 'description':
        return ctx.description;
      case 'personality':
        return ctx.personality;
      case 'scenario':
        return ctx.scenario;
      case 'persona':
        return ctx.userPersona;
      case 'lastmessage':
        return ctx.lastMessage;
      case 'lastusermessage':
        return ctx.lastUserMessage;
      case 'lastcharmessage':
        return ctx.lastCharMessage;
      case 'idle_duration':
      case 'idleduration':
        final d = ctx.idleDuration;
        return d == null ? null : _humanizeDuration(d);
      case 'group':
      case 'groupnotmuted':
        // No mute concept in FPAI — both list the full roster.
        return ctx.groupMemberNames?.join(', ') ?? ctx.characterName;
      case 'charifnotgroup':
        if (ctx.groupMemberNames != null) return '';
        return ctx.characterName;
      case 'notchar':
        final members = ctx.groupMemberNames;
        if (members == null) return null;
        return members.where((n) => n != ctx.characterName).join(', ');
    }
    return null;
  }

  static String _humanizeDuration(Duration d) {
    if (d.inMinutes < 1) return 'less than a minute';
    if (d.inMinutes < 60) {
      return '${d.inMinutes} minute${d.inMinutes == 1 ? '' : 's'}';
    }
    if (d.inHours < 24) return '${d.inHours} hour${d.inHours == 1 ? '' : 's'}';
    return '${d.inDays} day${d.inDays == 1 ? '' : 's'}';
  }

  /// Best-effort moment.js → ICU DateFormat token mapping for the common
  /// tokens ST cards actually use ({{datetimeformat::DD.MM.YYYY HH:mm}}…).
  static String _momentToIcu(String fmt) {
    return fmt
        .replaceAll('YYYY', 'yyyy')
        .replaceAll('YY', 'yy')
        .replaceAll('dddd', 'EEEE')
        .replaceAll('ddd', 'EEE')
        .replaceAll('DD', 'dd')
        .replaceAll('D', 'd')
        .replaceAll('A', 'a');
  }

  /// ST arg-splitting: `::` always splits on `::`; the single-colon form
  /// comma-splits for list macros (random/pick) with `\,` escaping, and is a
  /// single argument for everything else.
  static List<String> _splitArgs(String name, String? sep, String? argsStr) {
    if (argsStr == null) return const [];
    if (sep == '::') return argsStr.split('::');
    if (name == 'random' || name == 'pick') {
      return argsStr
          .split(_unescapedComma)
          .map((s) => s.trim().replaceAll(r'\,', ','))
          .where((s) => s.isNotEmpty)
          .toList();
    }
    return [argsStr];
  }
}
