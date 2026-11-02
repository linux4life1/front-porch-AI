// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The user's line as the transcript shows it once an `@Name` has done its
// routing job. The mention is an instruction to the app, not something said
// in the scene, so it never reaches the bubble or the prompt. Routing still
// reads the line as typed (see [kAtMentionRawTextMeta]).

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/scene_guest_director.dart';

/// Metadata key holding the line exactly as typed, set only when
/// [AtMentionText.clean] changed it. Routing that re-reads the line later
/// (the Away pulse on send and on Try again) reads this, so the `@` keeps
/// working after it has left the shown text. An edit drops it.
const kAtMentionRawTextMeta = 'at_mention_raw_text';

class AtMentionText {
  const AtMentionText._();

  // A noncharacter marks where a mention was, so the tidy-up only ever
  // touches the spots it emptied and never the rest of the user's line.
  static const _gap = '￿';

  /// [text] with every `@Name` of a [roster] member taken out, wherever it
  /// sits, and the spacing and punctuation around each gap tidied:
  /// "@Mara, what do you think?" and "what do you think, @Mara?" both read
  /// "what do you think?"; "Hey @Mara, how are you?" reads "Hey, how are
  /// you?"; "tell @Sam hi" reads "tell hi". A line that was nothing but
  /// mentions comes back empty. `@` that names nobody on the roster (an
  /// email, a handle, "@Mara-Lynn") is left alone.
  static String clean(String text, {required List<CharacterCard> roster}) {
    if (!text.contains('@') || text.contains(_gap)) return text;
    var out = text;
    for (final card in roster) {
      out = out.replaceAll(_mention(card.name), _gap);
    }
    if (out == text) return text;
    // A run of mentions is one gap: "@Mara and @Sam, dinner?" must not
    // leave a dangling "and".
    final run = RegExp(
      '$_gap[ \\t]*,?[ \\t]*(?:(?:and|or|&)[ \\t]+)?$_gap',
      caseSensitive: false,
    );
    while (run.hasMatch(out)) {
      out = out.replaceAll(run, _gap);
    }
    const sep = r'[,;:\-–—]';
    final rules = <(RegExp, String Function(Match))>[
      // Opening a line: the gap and the separator after it.
      (RegExp('(^|\\n)[ \\t]*$_gap[ \\t]*$sep*[ \\t]*'), (m) => m.group(1)!),
      // Closing a line: the separator before it; end punctuation stays.
      (
        RegExp('[ \\t]*$sep*[ \\t]*$_gap[ \\t]*(?=[.!?…]*[ \\t]*(\\n|\$))'),
        (_) => '',
      ),
      // Before punctuation mid-line: "Hey @Mara, how" -> "Hey, how", and
      // "hi, @Mara, there" -> "hi, there".
      (RegExp('[ \\t]*(?:$sep[ \\t]*)?$_gap[ \\t]*(?=[,.!?;:…])'), (_) => ''),
    ];
    while (out.contains(_gap)) {
      final before = out;
      for (final (re, to) in rules) {
        out = out.replaceAllMapped(re, to);
      }
      if (out == before) {
        // Mid-sentence between words: one space remains.
        out = out.replaceFirst(RegExp('[ \\t]*$_gap[ \\t]*'), ' ');
      }
    }
    // Only punctuation left ("@Sam!") is still a line of nothing but
    // mentions.
    if (RegExp(r'^[\s.,!?;:…\-–—]*$').hasMatch(out)) return '';
    return out.trim();
  }

  /// The roster member a line that is only `@Name` (once [clean]ed, empty)
  /// asks to hear from, or null when the line says something else.
  static CharacterCard? bareAddress(
    String text, {
    required List<CharacterCard> roster,
  }) {
    if (clean(text, roster: roster).isNotEmpty) return null;
    return SceneGuestDirector.atMentionedCard(roster, text);
  }

  /// The line routing should read: the typed line when [clean] changed it,
  /// else the shown line.
  static String routingText(ChatMessage m) {
    final raw = (m.activeMetadata ?? m.metadata)?[kAtMentionRawTextMeta];
    return raw is String ? raw : m.promptText;
  }

  /// Same boundaries as the router's matcher, longest variant first so
  /// "@Mara Vance" is taken whole rather than as "@Mara".
  static RegExp _mention(String name) {
    final variants = SceneGuestDirector.nameVariantsOf(name)
      ..sort((a, b) => b.length.compareTo(a.length));
    if (variants.isEmpty) return RegExp(r'(?!)');
    final alt = variants.map(RegExp.escape).join('|');
    return RegExp('(?<![\\w.\\-+])@(?:$alt)(?![\\w\\-])', caseSensitive: false);
  }
}
