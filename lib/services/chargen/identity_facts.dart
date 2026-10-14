// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Pure parse for the AI creator's identity facts pass: the Front Porch
// fields a profile implies (birthday, job, opening task and stance, lists,
// creator notes). The model answers words; Dart decides the numbers, so a
// birthday always agrees with the Age field and bond/trust stay in band.

import 'package:front_porch_ai/models/models.dart'
    show CharacterCard, FrontPorchExtensions;
import 'package:front_porch_ai/services/chargen/char_macro.dart';
import 'package:front_porch_ai/services/chargen/porch_life_identity.dart';
import 'package:front_porch_ai/services/chat/chat.dart'
    show formatWorkHoursRange, parseWorkHoursRange;

const kIdentityFactsToolName = 'set_identity_facts';

/// How the character stands with {{user}} as the story opens.
const kRelationshipWarmths = ['strangers', 'warm', 'guarded', 'cold'];

/// Bond and trust per warmth: (shortTermBond, trustLevel).
const _warmthBands = {
  'strangers': (0, 0),
  'warm': (15, 15),
  'guarded': (0, 0),
  'cold': (-15, -10),
};

/// Whether [relationship] names someone {{user}} already is to the
/// character. Empty, "Stranger(s)" and "None" do not: the interview skips
/// its relationship question and the facts pass opens as strangers.
bool hasRelationshipToUser(String relationship) {
  final r = relationship.trim().toLowerCase();
  return r.isNotEmpty && r != 'stranger' && r != 'strangers' && r != 'none';
}

/// The facts one pass reads from a profile. Also the relay's JSON shape
/// ([toJson] / [IdentityFacts.fromJson]).
class IdentityFacts {
  const IdentityFacts({
    this.birthday = '',
    this.occupation = '',
    this.occupationBrief = '',
    this.hours = '',
    this.workDays,
    this.currentTask = '',
    this.warmth = 'strangers',
    this.shortTermBond = 0,
    this.trustLevel = 0,
    this.ambitions = const [],
    this.planLines = const [],
    this.likes = const [],
    this.dislikes = const [],
    this.intimateInto = const [],
    this.intimateNotInto = const [],
    this.creatorNotes = '',
  });

  /// `YYYY-MM-DD`, consistent with the Age field; '' when unknown.
  final String birthday;
  final String occupation;
  final String occupationBrief;

  /// The picker's format ("9am–5pm"); '' when no job or no clock range.
  final String hours;

  /// `DateTime.weekday` ints; null leaves the Mon–Fri default.
  final List<int>? workDays;
  final String currentTask;

  /// One of [kRelationshipWarmths]; [shortTermBond] and [trustLevel] follow.
  final String warmth;
  final int shortTermBond;
  final int trustLevel;
  final List<String> ambitions;
  final List<String> planLines;
  final List<String> likes;
  final List<String> dislikes;
  final List<String> intimateInto;
  final List<String> intimateNotInto;

  /// A two or three sentence pitch, the character's name as `{{char}}`.
  final String creatorNotes;

  bool get isEmpty =>
      birthday.isEmpty &&
      occupation.isEmpty &&
      currentTask.isEmpty &&
      ambitions.isEmpty &&
      planLines.isEmpty &&
      likes.isEmpty &&
      dislikes.isEmpty &&
      intimateInto.isEmpty &&
      intimateNotInto.isEmpty &&
      creatorNotes.isEmpty;

  Map<String, dynamic> toJson() => {
    'birthday': birthday,
    'occupation': occupation,
    'occupationBrief': occupationBrief,
    'hours': hours,
    'workDays': workDays,
    'currentTask': currentTask,
    'warmth': warmth,
    'shortTermBond': shortTermBond,
    'trustLevel': trustLevel,
    'ambitions': ambitions,
    'planLines': planLines,
    'likes': likes,
    'dislikes': dislikes,
    'intimateInto': intimateInto,
    'intimateNotInto': intimateNotInto,
    'creatorNotes': creatorNotes,
  };

  /// Tolerant read of [toJson]'s shape (a phone may send it back edited).
  factory IdentityFacts.fromJson(Map<String, dynamic> j) {
    String s(String k) => j[k] is String ? j[k] as String : '';
    int n(String k) => j[k] is num ? (j[k] as num).toInt() : 0;
    List<String> l(String k) => [
      if (j[k] is List)
        for (final v in j[k] as List)
          if (v is String && v.trim().isNotEmpty) v,
    ];
    final days = j['workDays'];
    final warmth = s('warmth');
    return IdentityFacts(
      birthday: s('birthday'),
      occupation: s('occupation'),
      occupationBrief: s('occupationBrief'),
      hours: s('hours'),
      workDays: days is List ? _weekdays(days) : null,
      currentTask: s('currentTask'),
      warmth: kRelationshipWarmths.contains(warmth) ? warmth : 'strangers',
      shortTermBond: n('shortTermBond'),
      trustLevel: n('trustLevel'),
      ambitions: l('ambitions'),
      planLines: l('planLines'),
      likes: l('likes'),
      dislikes: l('dislikes'),
      intimateInto: l('intimateInto'),
      intimateNotInto: l('intimateNotInto'),
      creatorNotes: s('creatorNotes'),
    );
  }
}

const _kFactChipKeys = [
  'ambitions',
  'plan_lines',
  'likes',
  'dislikes',
  'intimate_into',
  'intimate_not_into',
  'work_days',
];
const _kFactScalarKeys = [
  'birthday_month',
  'birthday_day',
  'birth_year',
  'occupation',
  'occupation_brief',
  'hours',
  'current_task',
  'relationship_warmth',
  'creator_notes',
];

/// Read the facts from a tool call's arguments or a model's text.
/// [age] and [today] fix the birthday's year; [relationship] that is not
/// one ([hasRelationshipToUser]) forces strangers; [name] becomes `{{char}}`
/// in the creator notes. Intimate lists only when [nsfw].
IdentityFacts parseIdentityFacts(
  Object? raw, {
  required bool nsfw,
  required String age,
  required String relationship,
  String name = '',
  DateTime? today,
}) {
  final map = porchLifeJsonMap(
    raw,
    chipKeys: _kFactChipKeys,
    scalarKeys: _kFactScalarKeys,
  );
  if (map == null) return const IdentityFacts();
  String text(String key, int max) {
    final v = map[key];
    if (v is! String) return '';
    final t = v.trim();
    return t.length > max ? t.substring(0, max).trim() : t;
  }

  final occupation = text('occupation', 60);
  final range = parseWorkHoursRange(text('hours', 40));
  final days = map['work_days'];
  final warmth = hasRelationshipToUser(relationship)
      ? _warmth(map['relationship_warmth'])
      : 'strangers';
  final band = _warmthBands[warmth]!;
  return IdentityFacts(
    birthday: composeBirthday(
      month: map['birthday_month'],
      day: map['birthday_day'],
      birthYear: map['birth_year'],
      age: age,
      today: today ?? DateTime.now(),
    ),
    occupation: occupation,
    occupationBrief: occupation.isEmpty ? '' : text('occupation_brief', 300),
    hours: occupation.isEmpty || range == null
        ? ''
        : formatWorkHoursRange(range.$1, range.$2),
    workDays: occupation.isEmpty || days is! List || days.isEmpty
        ? null
        : _weekdays(days),
    currentTask: text('current_task', 240),
    warmth: warmth,
    shortTermBond: band.$1,
    trustLevel: band.$2,
    ambitions: porchLifeChips(map['ambitions']),
    planLines: porchLifeChips(map['plan_lines'], cap: 6, maxLen: 160),
    likes: porchLifeChips(map['likes']),
    dislikes: porchLifeChips(map['dislikes']),
    intimateInto: nsfw ? porchLifeChips(map['intimate_into']) : const [],
    intimateNotInto: nsfw ? porchLifeChips(map['intimate_not_into']) : const [],
    creatorNotes: applyCharMacro(text('creator_notes', 600), name),
  );
}

String _warmth(Object? raw) {
  final w = raw is String ? raw.trim().toLowerCase() : '';
  if (w == 'stranger') return 'strangers';
  return kRelationshipWarmths.contains(w) ? w : 'strangers';
}

const _dayNames = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];

List<int>? _weekdays(List raw) {
  final out = <int>{};
  for (final v in raw) {
    final n = v is num
        ? v.toInt()
        : int.tryParse('$v') ??
              _dayNames.indexWhere(
                    (d) => '$v'.trim().toLowerCase().startsWith(d),
                  ) +
                  1;
    if (n >= 1 && n <= 7) out.add(n);
  }
  return out.isEmpty ? null : (out.toList()..sort());
}

const _monthNames = [
  'jan',
  'feb',
  'mar',
  'apr',
  'may',
  'jun',
  'jul',
  'aug',
  'sep',
  'oct',
  'nov',
  'dec',
];
const _monthDays = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];

int? _int(Object? raw) {
  if (raw is num) return raw.toInt();
  if (raw is! String) return null;
  final t = raw.trim().toLowerCase();
  final n = int.tryParse(t);
  if (n != null) return n;
  final m = _monthNames.indexWhere((name) => t.startsWith(name));
  return m < 0 ? null : m + 1;
}

/// A `YYYY-MM-DD` birthday from the model's [month] and [day] whose age on
/// [today] is the first number in [age]. [birthYear] is read only when
/// [age] is blank. Feb 29 becomes Feb 28 (the card rejects Feb 29); an
/// impossible date, or no year to be had, is ''.
String composeBirthday({
  required Object? month,
  required Object? day,
  Object? birthYear,
  required String age,
  required DateTime today,
}) {
  final m = _int(month);
  var d = _int(day);
  if (m == null || d == null || m < 1 || m > 12 || d < 1) return '';
  if (m == 2 && d == 29) d = 28;
  if (d > _monthDays[m - 1]) return '';
  final years = int.tryParse(RegExp(r'\d+').firstMatch(age)?.group(0) ?? '');
  int? year;
  if (years != null) {
    final later = m > today.month || (m == today.month && d > today.day);
    year = today.year - years - (later ? 1 : 0);
  } else if (age.trim().isEmpty) {
    year = _int(birthYear);
  }
  if (year == null || year < 1 || year > today.year) return '';
  String two(int v) => v.toString().padLeft(2, '0');
  return '${year.toString().padLeft(4, '0')}-${two(m)}-${two(d)}';
}

/// The tool the facts pass asks for. Intimate lists only when [nsfw].
List<Map<String, dynamic>> identityFactsToolSchema({required bool nsfw}) {
  Map<String, dynamic> str(String d) => {'type': 'string', 'description': d};
  Map<String, dynamic> chips(String d) => {
    'type': 'array',
    'items': {'type': 'string'},
    'description': d,
  };
  return [
    {
      'type': 'function',
      'function': {
        'name': kIdentityFactsToolName,
        'description':
            'Record the facts this character profile implies: birthday, '
            'work, what they are doing as the story opens, how they stand '
            'with {{user}}, their wants and tastes, and a short pitch.',
        'parameters': {
          'type': 'object',
          'properties': {
            'birthday_month': {'type': 'integer', 'minimum': 1, 'maximum': 12},
            'birthday_day': {'type': 'integer', 'minimum': 1, 'maximum': 31},
            'birth_year': {
              'type': 'integer',
              'description': 'Only when no age is given.',
            },
            'occupation': str('Their job, or "" if they have none.'),
            'occupation_brief': str('One sentence on what that work is like.'),
            'hours': str('Usual working hours, 24-hour "HH:MM-HH:MM".'),
            'work_days': {
              'type': 'array',
              'items': {'type': 'integer', 'minimum': 1, 'maximum': 7},
              'description': 'Days they work, 1 = Monday ... 7 = Sunday.',
            },
            'current_task': str(
              'What they are doing or after as the story opens, in their '
              'own voice, one sentence.',
            ),
            'relationship_warmth': {
              'type': 'string',
              'enum': kRelationshipWarmths,
            },
            'ambitions': chips('2-4 long-term goals across the whole story.'),
            'plan_lines': chips('2-4 short sentences: how they mean to go on.'),
            'likes': chips('3-6 small specific things they warm to.'),
            'dislikes': chips('2-4 things that make them bristle.'),
            if (nsfw)
              'intimate_into': chips('Suggestive tastes for 18+ scenes.'),
            if (nsfw)
              'intimate_not_into': chips('Hard limits / not interested.'),
            'creator_notes': str(
              'A two or three sentence pitch for this character. No real '
              'people\'s names.',
            ),
          },
          'required': [
            'birthday_month',
            'birthday_day',
            'current_task',
            'relationship_warmth',
            'ambitions',
            'likes',
            'dislikes',
            'creator_notes',
          ],
        },
      },
    },
  ];
}

/// Write [f] onto [card]: the Front Porch fields and the creator notes. An
/// empty value keeps what the card had, so a partial read never wipes a
/// field; bond and trust are always written. Settings and instructions
/// (chaos, needs baselines, verification, prompts) are never touched.
/// When [nsfw] is false the intimate lists are cleared: a card whose 18+
/// was switched off must not keep (and export) them.
void applyIdentityFacts(
  CharacterCard card,
  IdentityFacts f, {
  bool nsfw = true,
}) {
  final prior = card.frontPorchExtensions;
  String keep(String next, String old) => next.isEmpty ? old : next;
  List<String> keepList(List<String> next, List<String> old) =>
      next.isEmpty ? old : List.unmodifiable(next);
  final base = prior ?? _freshExtensions();
  card.frontPorchExtensions = base.copyWith(
    birthday: keep(f.birthday, base.birthday),
    occupation: keep(f.occupation, base.occupation),
    occupationBrief: keep(f.occupationBrief, base.occupationBrief),
    hours: keep(f.hours, base.hours),
    workDays: f.workDays,
    currentTask: keep(f.currentTask, base.currentTask),
    shortTermBond: f.shortTermBond,
    trustLevel: f.trustLevel,
    ambitions: keepList(f.ambitions, base.ambitions),
    planLines: keepList(f.planLines, base.planLines),
    likes: keepList(f.likes, base.likes),
    dislikes: keepList(f.dislikes, base.dislikes),
    intimateInto: nsfw ? keepList(f.intimateInto, base.intimateInto) : const [],
    intimateNotInto: nsfw
        ? keepList(f.intimateNotInto, base.intimateNotInto)
        : const [],
  );
  if (f.creatorNotes.isNotEmpty) card.creatorNotes = f.creatorNotes;
}

FrontPorchExtensions _freshExtensions() =>
    FrontPorchExtensions(needsSimEnabled: true);
