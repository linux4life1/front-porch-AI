// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Reads the profile rewrite's JSON while it streams, so the Profile step
// (desktop and phone) can show the description being written inside its
// box and move the "Writing…" header to Personality when that key arrives.
// Pure and tolerant: a preamble before the object, escapes, a stray
// unescaped quote inside a value, and a half-received escape are all fine.

/// The three profile fields a rewrite writes, and `none` before any.
enum ProfileField { none, description, personality, scenario }

/// What a partial rewrite shows so far.
class ProfileStreamView {
  const ProfileStreamView({
    this.writing = ProfileField.none,
    this.texts = const {},
    this.finished = const {},
  });

  /// The field whose key arrived last: the one being written, or the one
  /// just finished until the next key appears. `none` before any.
  final ProfileField writing;

  /// Each started field's text so far, unescaped.
  final Map<ProfileField, String> texts;

  /// Fields whose value has closed.
  final Set<ProfileField> finished;

  String get description => texts[ProfileField.description] ?? '';
  String get personality => texts[ProfileField.personality] ?? '';
  String get scenario => texts[ProfileField.scenario] ?? '';

  bool started(ProfileField f) => texts.containsKey(f);
}

const _keys = {
  'description': ProfileField.description,
  'personality': ProfileField.personality,
  'scenario': ProfileField.scenario,
};

/// [partialJson] read as far as it goes (see [ProfileStreamView]).
ProfileStreamView parseProfileStream(String partialJson) {
  final s = partialJson;
  var i = s.indexOf('{');
  if (i < 0) return const ProfileStreamView();
  i++;
  var writing = ProfileField.none;
  final texts = <ProfileField, String>{};
  final finished = <ProfileField>{};

  int skipWs(int at) {
    while (at < s.length && ' \t\r\n'.contains(s[at])) {
      at++;
    }
    return at;
  }

  while (true) {
    i = skipWs(i);
    while (i < s.length && s[i] == ',') {
      i = skipWs(i + 1);
    }
    if (i >= s.length || s[i] != '"') break;
    // The key.
    final keyEnd = s.indexOf('"', i + 1);
    if (keyEnd < 0) break;
    final field = _keys[s.substring(i + 1, keyEnd)];
    i = skipWs(keyEnd + 1);
    if (i >= s.length || s[i] != ':') break;
    i = skipWs(i + 1);
    if (i >= s.length) {
      if (field != null) {
        writing = field;
        texts[field] = '';
      }
      break;
    }
    if (s[i] != '"') {
      // A non-string value (number, list): skip to the next key.
      final next = s.indexOf(RegExp(r',\s*"'), i);
      if (next < 0) break;
      i = next;
      continue;
    }
    if (field != null) {
      writing = field;
      texts[field] = '';
    }
    final value = StringBuffer();
    var closed = false;
    i++;
    while (i < s.length) {
      final c = s[i];
      if (c == r'\') {
        if (i + 1 >= s.length) break;
        final e = s[i + 1];
        if (e == 'u') {
          if (i + 6 > s.length) break;
          final code = int.tryParse(s.substring(i + 2, i + 6), radix: 16);
          if (code != null) value.writeCharCode(code);
          i += 6;
          continue;
        }
        value.write(switch (e) {
          'n' => '\n',
          't' => '\t',
          'r' => '',
          _ => e,
        });
        i += 2;
        continue;
      }
      if (c == '"' && _closes(s, i + 1, skipWs)) {
        closed = true;
        i++;
        break;
      }
      value.write(c);
      i++;
    }
    if (field != null) {
      texts[field] = value.toString();
      if (closed) finished.add(field);
    }
    if (!closed) break;
  }
  return ProfileStreamView(writing: writing, texts: texts, finished: finished);
}

/// Whether a quote before [at] ends its value: what follows is the end of
/// what has arrived, `}`, or a comma and then a key. Anything else means
/// the model left a quote unescaped inside the text.
bool _closes(String s, int at, int Function(int) skipWs) {
  final j = skipWs(at);
  if (j >= s.length || s[j] == '}') return true;
  if (s[j] != ',') return false;
  final k = skipWs(j + 1);
  return k >= s.length || s[k] == '"';
}
