import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SpellCheckResults, SuggestionSpan;

import 'package:front_porch_ai/services/services.dart'
    show DesktopSpellCheckService;
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/app_text_field.dart';
import 'package:front_porch_ai/ui/widgets/styled_text_tokenizer.dart';

export 'styled_text_tokenizer.dart';

class StyledTextController extends TextEditingController
    implements SpellCheckResultsProvider {
  static final _spellService = DesktopSpellCheckService();

  final StyledTextPreset preset;

  StyledTextController({super.text, StyledTextPreset? preset})
    : preset = preset ?? StyledTextPreset.prose {
    addListener(_onTextChanged);
  }

  // ── Spell check cache ──
  String? _lastCheckedText;
  final List<TextRange> _misspelledRanges = [];
  final Map<int, List<String>> _suggestions = {};
  Timer? _spellDebounce;
  bool _spellCheckInFlight = false;
  bool _ignoreTextChange = false;

  /// dispose() cancels the debounce timer, but an ALREADY-IN-FLIGHT async
  /// spell check resumes after its await and used to notifyListeners() on
  /// the dead controller — "used after being disposed", surfaced by the
  /// message-actions E2E typing into the edit dialog and saving before the
  /// fetch returned. Every async resume point checks this flag.
  bool _disposed = false;

  void applySpellResults(String checkedText, List<SuggestionSpan> spans) {
    _lastCheckedText = checkedText;
    _misspelledRanges
      ..clear()
      ..addAll(spans.map((s) => s.range));
    _misspelledRanges.sort((a, b) => a.start.compareTo(b.start));
    _suggestions
      ..clear()
      ..addEntries(spans.map((s) => MapEntry(s.range.start, s.suggestions)));
  }

  void clearSpellResults() {
    _lastCheckedText = null;
    _misspelledRanges.clear();
    _suggestions.clear();
  }

  @override
  SpellCheckResults? get spellCheckResults {
    if (_misspelledRanges.isEmpty || _lastCheckedText != text) return null;
    return SpellCheckResults(
      _lastCheckedText!,
      _misspelledRanges.map((r) {
        return SuggestionSpan(r, _suggestions[r.start] ?? <String>[]);
      }).toList(),
    );
  }

  // ── Spell check orchestration ──

  void _onTextChanged() {
    if (_ignoreTextChange) return;
    _spellDebounce?.cancel();
    _spellDebounce = Timer(const Duration(milliseconds: 300), _trySpellCheck);
  }

  void _trySpellCheck() {
    // Skip entirely when the user turned spell check off, rather than making a
    // channel round trip only to throw the answer away. This controller fires
    // on a 300ms debounce after every keystroke pause in the chat composer and
    // both character editors, so the wasted work is not hypothetical.
    if (!_spellCheckInFlight &&
        !_disposed &&
        DesktopSpellCheckService.isEnabled) {
      _runSpellCheck();
    }
  }

  Future<void> _runSpellCheck() async {
    if (_spellCheckInFlight || _disposed) return;
    _spellCheckInFlight = true;
    final text = this.text;
    _ignoreTextChange = true;
    try {
      if (text.trim().isEmpty) {
        clearSpellResults();
        notifyListeners();
        return;
      }
      // The locale is a formality — the service ignores it and uses the
      // configured spell check language instead. Passing the OS locale here
      // (as this used to, meaningfully) is what made a German desktop check
      // English role-play against a German dictionary.
      final results = await _spellService.fetchSpellCheckSuggestions(
        const Locale('en', 'US'),
        text,
      );
      if (_disposed) return; // resumed after dispose — never touch state
      if (text != this.text) return;
      if (results != null && results.isNotEmpty) {
        applySpellResults(text, results);
      } else {
        clearSpellResults();
      }
      notifyListeners();
    } catch (e) {
      debugPrint('Spell check error: $e');
      if (_disposed) return; // the error may BE the disposed assert
      clearSpellResults();
      notifyListeners();
    } finally {
      _ignoreTextChange = false;
      _spellCheckInFlight = false;
      if (!_disposed && text != this.text) {
        _spellDebounce?.cancel();
        _spellDebounce = Timer(
          const Duration(milliseconds: 300),
          _trySpellCheck,
        );
      }
    }
  }

  // ── Styled text span building ──

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final text = this.text;
    final useSpellCheck =
        _lastCheckedText == text && _misspelledRanges.isNotEmpty;

    final segments = <({String text, TextStyle? style, int offset})>[];
    int lastEnd = 0;

    void addSegment(String segText, TextStyle? segStyle, int segOffset) {
      segments.add((text: segText, style: segStyle, offset: segOffset));
    }

    if (preset.usePriorityTokenization) {
      for (final match in _tokenizeWithPriority(text)) {
        if (match.start > lastEnd) {
          addSegment(text.substring(lastEnd, match.start), style, lastEnd);
        }
        TextStyle? segStyle;
        switch (match.type) {
          case StyledTokenType.dialogue:
            segStyle = (style ?? const TextStyle()).copyWith(
              color: AppColors.resolve(
                context,
                Colors.amberAccent,
                const Color(0xFFB45309),
              ),
              fontWeight: FontWeight.w500,
            );
          case StyledTokenType.action:
            segStyle = (style ?? const TextStyle()).copyWith(
              color: AppColors.resolve(
                context,
                const Color(0xFF90CAF9),
                const Color(0xFF1565C0),
              ),
            );
          case StyledTokenType.macro:
            segStyle = (style ?? const TextStyle()).copyWith(
              color: AppColors.resolve(
                context,
                Colors.tealAccent,
                const Color(0xFF0D9488),
              ),
            );
        }
        addSegment(match.matchText, segStyle, match.start);
        lastEnd = match.end;
      }
    } else {
      for (final m in preset.pattern.allMatches(text)) {
        if (m.start > lastEnd) {
          addSegment(text.substring(lastEnd, m.start), style, lastEnd);
        }
        addSegment(
          m.group(0)!,
          preset.styler(context, m.group(0)!, style),
          m.start,
        );
        lastEnd = m.end;
      }
    }
    if (segments.isEmpty) {
      addSegment(text, style, 0);
    } else if (lastEnd < text.length) {
      addSegment(text.substring(lastEnd), style, lastEnd);
    }

    if (!useSpellCheck) {
      return TextSpan(
        children: segments
            .map((s) => TextSpan(text: s.text, style: s.style))
            .toList(),
        style: style,
      );
    }

    const misspelledTextStyle = TextStyle(
      decoration: TextDecoration.underline,
      decorationColor: Colors.redAccent,
      decorationStyle: TextDecorationStyle.wavy,
    );

    final children = <TextSpan>[];
    for (final seg in segments) {
      final spanStart = seg.offset;
      final spanEnd = seg.offset + seg.text.length;

      final intersecting = <({int start, int end})>[];
      for (final range in _misspelledRanges) {
        final isectStart = range.start > spanStart ? range.start : spanStart;
        final isectEnd = range.end < spanEnd ? range.end : spanEnd;
        if (isectStart < isectEnd) {
          intersecting.add((start: isectStart, end: isectEnd));
        }
      }

      if (intersecting.isEmpty) {
        children.add(TextSpan(text: seg.text, style: seg.style));
        continue;
      }

      int splitAt = 0;
      for (final isect in intersecting) {
        final localStart = (isect.start - seg.offset).clamp(0, seg.text.length);
        if (localStart > splitAt) {
          children.add(
            TextSpan(
              text: seg.text.substring(splitAt, localStart),
              style: seg.style,
            ),
          );
        }
        final localEnd = (isect.end - seg.offset).clamp(0, seg.text.length);
        children.add(
          TextSpan(
            text: seg.text.substring(localStart, localEnd),
            style: seg.style?.merge(misspelledTextStyle) ?? misspelledTextStyle,
          ),
        );
        splitAt = localEnd;
      }
      if (splitAt < seg.text.length) {
        children.add(
          TextSpan(text: seg.text.substring(splitAt), style: seg.style),
        );
      }
    }

    return TextSpan(children: children, style: style);
  }

  @override
  void dispose() {
    _disposed = true;
    _spellDebounce?.cancel();
    super.dispose();
  }

  /// Tokenizes [text] with priority: [{{}}] > [""] > [**].
  ///
  /// Uses char-by-char scanning for [""] and [**] so that their delimiters
  /// are ignored when they fall inside already-matched higher-priority spans.
  /// This ensures macros always retain teal coloring even when nested
  /// inside quotes or asterisks, and vice versa.
  Iterable<({int start, int end, String matchText, StyledTokenType type})>
  _tokenizeWithPriority(String text) {
    // Phase 1: Macro (highest priority) — regex is safe, no delimiter overlap.
    final macroMatches = RegExp(r'{{[^}]*}}').allMatches(text).toList();
    final macroRanges = <({int start, int end})>[
      for (final mm in macroMatches) (start: mm.start, end: mm.end),
    ];

    // Phase 2: Dialogue (medium priority) — char-by-char scan,
    // skipping " delimiters that land inside macro spans.
    final dialogueRanges = scanDialogue(text, macroRanges);

    // Phase 3: Action (lowest priority) — char-by-char scan,
    // skipping * delimiters that land inside macro or dialogue spans.
    final combinedSkip = <({int start, int end})>[
      ...macroRanges,
      ...dialogueRanges,
    ]..sort((a, b) => a.start.compareTo(b.start));
    final actionRanges = scanDelimited(text, '*', '*', combinedSkip);

    // Split dialogue ranges around macro ranges inside them.
    final dialogueSplits = <({int start, int end})>[];
    for (final dr in dialogueRanges) {
      int segStart = dr.start;
      for (final mr in macroRanges) {
        if (mr.start >= dr.start && mr.end <= dr.end) {
          if (segStart < mr.start) {
            dialogueSplits.add((start: segStart, end: mr.start));
          }
          segStart = mr.end;
        }
      }
      if (segStart < dr.end) {
        dialogueSplits.add((start: segStart, end: dr.end));
      }
    }

    // Split action ranges around macro and dialogue splits inside them.
    final actionSplitRanges = <({int start, int end})>[
      ...macroRanges,
      ...dialogueSplits,
    ]..sort((a, b) => a.start.compareTo(b.start));

    final actionSplits = <({int start, int end})>[];
    for (final ar in actionRanges) {
      int segStart = ar.start;
      for (final sr in actionSplitRanges) {
        if (sr.start >= ar.start && sr.end <= ar.end) {
          if (segStart < sr.start) {
            actionSplits.add((start: segStart, end: sr.start));
          }
          segStart = sr.end;
        }
      }
      if (segStart < ar.end) {
        actionSplits.add((start: segStart, end: ar.end));
      }
    }

    return <({int start, int end, String matchText, StyledTokenType type})>[
      for (final mm in macroMatches)
        (
          start: mm.start,
          end: mm.end,
          matchText: mm.group(0)!,
          type: StyledTokenType.macro,
        ),
      for (final d in dialogueSplits)
        (
          start: d.start,
          end: d.end,
          matchText: text.substring(d.start, d.end),
          type: StyledTokenType.dialogue,
        ),
      for (final a in actionSplits)
        (
          start: a.start,
          end: a.end,
          matchText: text.substring(a.start, a.end),
          type: StyledTokenType.action,
        ),
    ]..sort((a, b) => a.start.compareTo(b.start));
  }
}
