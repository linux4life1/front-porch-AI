import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/ui/widgets/widgets.dart';

Widget _buildApp() {
  return const MaterialApp(home: Scaffold(body: SizedBox.shrink()));
}

Widget _buildDarkApp() {
  return MaterialApp(
    theme: ThemeData.dark(),
    home: const Scaffold(body: SizedBox.shrink()),
  );
}

BuildContext _pumpContext(WidgetTester tester) {
  return tester.element(find.byType(SizedBox));
}

void main() {
  group('SuggestionSpan API compatibility', () {
    test('SuggestionSpan.range is accessible', () {
      final span = SuggestionSpan(TextRange(start: 0, end: 5), ['hello']);
      expect(span.range.start, 0);
      expect(span.range.end, 5);
    });

    test('SuggestionSpan.suggestions is accessible', () {
      final span = SuggestionSpan(TextRange(start: 0, end: 5), [
        'hello',
        'world',
      ]);
      expect(span.suggestions, hasLength(2));
    });
  });

  group('SpellCheckResults API compatibility', () {
    test('SpellCheckResults.spellCheckedText is accessible', () {
      final results = SpellCheckResults('hello world', [
        SuggestionSpan(TextRange(start: 0, end: 5), ['hello']),
      ]);
      expect(results.spellCheckedText, 'hello world');
    });

    test('SpellCheckResults.suggestionSpans is accessible', () {
      final results = SpellCheckResults('hello world', [
        SuggestionSpan(TextRange(start: 0, end: 5), ['hello']),
      ]);
      expect(results.suggestionSpans, hasLength(1));
    });
  });

  group('StyledTextController.spellCheckResults getter', () {
    test('returns SpellCheckResults when cache is populated', () {
      final ctrl = StyledTextController()..text = 'hello world';
      ctrl.applySpellResults('hello world', [
        SuggestionSpan(TextRange(start: 6, end: 11), ['world']),
      ]);
      final results = ctrl.spellCheckResults;
      expect(results?.spellCheckedText, 'hello world');
      expect(results?.suggestionSpans, hasLength(1));
      expect(results?.suggestionSpans[0].suggestions, ['world']);
    });

    test('returns null when cache is empty', () {
      final ctrl = StyledTextController()..text = 'hello world';
      expect(ctrl.spellCheckResults, isNull);
    });

    test('returns null when text changed since last check', () {
      final ctrl = StyledTextController()..text = 'hello';
      ctrl.applySpellResults('hello', [
        SuggestionSpan(TextRange(start: 0, end: 5), ['hello']),
      ]);
      ctrl.text = 'changed';
      expect(ctrl.spellCheckResults, isNull);
    });

    test('clears after clearSpellResults', () {
      final ctrl = StyledTextController()..text = 'hello';
      ctrl.applySpellResults('hello', [
        SuggestionSpan(TextRange(start: 0, end: 5), ['hello']),
      ]);
      ctrl.clearSpellResults();
      expect(ctrl.spellCheckResults, isNull);
    });
  });

  group('StyledTextController.buildTextSpan override', () {
    testWidgets('accepts the standard parameters', (tester) async {
      await tester.pumpWidget(_buildApp());
      final ctrl = StyledTextController();
      final span = ctrl.buildTextSpan(
        context: _pumpContext(tester),
        style: null,
        withComposing: false,
      );
      expect(span, isA<TextSpan>());
    });

    testWidgets('produces colored spans for dialogue markers', (tester) async {
      await tester.pumpWidget(_buildApp());
      final ctrl = StyledTextController()..text = 'She said "hello" nicely';
      final span = ctrl.buildTextSpan(
        context: _pumpContext(tester),
        style: const TextStyle(color: Colors.white),
        withComposing: false,
      );
      expect(span.children, isNotNull);
      ctrl.dispose();
    });

    testWidgets('applies wavy underline for misspelled ranges', (tester) async {
      await tester.pumpWidget(_buildApp());
      final ctrl = StyledTextController()..text = '"hello" world';
      ctrl.applySpellResults('"hello" world', [
        SuggestionSpan(TextRange(start: 8, end: 13), ['world']),
      ]);
      final span = ctrl.buildTextSpan(
        context: _pumpContext(tester),
        style: const TextStyle(color: Colors.white),
        withComposing: false,
      );
      expect(span.children, hasLength(greaterThan(1)));
      ctrl.dispose();
    });
  });

  group('SpellCheckResultsProvider interface', () {
    test('StyledTextController implements SpellCheckResultsProvider', () {
      expect(StyledTextController(), isA<SpellCheckResultsProvider>());
    });
  });

  // ── StyledTextPreset — pattern matching ──

  group('StyledTextPreset pattern matching', () {
    test('prose matches dialogue, action, and macro markers', () {
      final matches = StyledTextPreset.prose.pattern
          .allMatches('say "hi" *waves* {{system}}')
          .toList();
      expect(matches, hasLength(3));
      expect(matches[0].group(0), '"hi"');
      expect(matches[1].group(0), '*waves*');
      expect(matches[2].group(0), '{{system}}');
    });

    test('prose does not match plain text', () {
      final matches =
          StyledTextPreset.prose.pattern.allMatches('hello world').toList();
      expect(matches, isEmpty);
    });

    test('macros matches only {{}} markers', () {
      final matches = StyledTextPreset.macros.pattern
          .allMatches('"hi" **waves** {{system}}')
          .toList();
      expect(matches, hasLength(1));
      expect(matches[0].group(0), '{{system}}');
    });

    test('macros does not match dialogue or action markers', () {
      final matches = StyledTextPreset.macros.pattern
          .allMatches('"hello" **world**')
          .toList();
      expect(matches, isEmpty);
    });

    test('accepts custom pattern and styler', () {
      final custom = StyledTextPreset(
        RegExp(r'\{[^}]+\}'),
        (ctx, match, base) => const TextStyle(color: Colors.purple),
      );
      final matches =
          custom.pattern.allMatches('before {custom} after').toList();
      expect(matches, hasLength(1));
      expect(matches[0].group(0), '{custom}');
    });
  });

  // ── StyledTextPreset — styler coloring (light + dark theme) ──

  group('StyledTextPreset styler coloring', () {
    // Light theme
    testWidgets('prose dialogue "" — light theme', (tester) async {
      await tester.pumpWidget(_buildApp());
      final style =
          StyledTextPreset.prose.styler(_pumpContext(tester), '"hello"', null);
      expect(style.color, const Color(0xFFB45309));
      expect(style.fontWeight, FontWeight.w500);
    });

    testWidgets('prose action ** — light theme', (tester) async {
      await tester.pumpWidget(_buildApp());
      final style =
          StyledTextPreset.prose.styler(_pumpContext(tester), '**waves**', null);
      expect(style.color, const Color(0xFF1565C0));
    });

    testWidgets('prose macro {{}} — light theme', (tester) async {
      await tester.pumpWidget(_buildApp());
      final style = StyledTextPreset.prose.styler(
        _pumpContext(tester),
        '{{system}}',
        null,
      );
      expect(style.color, const Color(0xFF0D9488));
    });

    testWidgets('macros macro {{}} — light theme', (tester) async {
      await tester.pumpWidget(_buildApp());
      final style = StyledTextPreset.macros.styler(
        _pumpContext(tester),
        '{{name}}',
        null,
      );
      expect(style.color, const Color(0xFF0D9488));
    });

    // Dark theme
    testWidgets('prose dialogue "" — dark theme', (tester) async {
      await tester.pumpWidget(_buildDarkApp());
      final style =
          StyledTextPreset.prose.styler(_pumpContext(tester), '"hello"', null);
      expect(style.color, Colors.amberAccent);
      expect(style.fontWeight, FontWeight.w500);
    });

    testWidgets('prose action ** — dark theme', (tester) async {
      await tester.pumpWidget(_buildDarkApp());
      final style =
          StyledTextPreset.prose.styler(_pumpContext(tester), '**waves**', null);
      expect(style.color, const Color(0xFF90CAF9));
    });

    testWidgets('prose macro {{}} — dark theme', (tester) async {
      await tester.pumpWidget(_buildDarkApp());
      final style = StyledTextPreset.prose.styler(
        _pumpContext(tester),
        '{{system}}',
        null,
      );
      expect(style.color, Colors.tealAccent);
    });

    testWidgets('macros macro {{}} — dark theme', (tester) async {
      await tester.pumpWidget(_buildDarkApp());
      final style = StyledTextPreset.macros.styler(
        _pumpContext(tester),
        '{{name}}',
        null,
      );
      expect(style.color, Colors.tealAccent);
    });
  });

  // ── StyledTextController — preset selection ──

  group('StyledTextController preset selection', () {
    test('default preset is prose', () {
      final ctrl = StyledTextController();
      expect(ctrl.preset, same(StyledTextPreset.prose));
    });

    test('explicit macros preset is accepted', () {
      final ctrl = StyledTextController(preset: StyledTextPreset.macros);
      expect(ctrl.preset, same(StyledTextPreset.macros));
    });

    test('initial text from constructor', () {
      final ctrl = StyledTextController(text: 'hello');
      expect(ctrl.text, 'hello');
    });
  });

  // ── buildTextSpan — macros preset ──

  group('buildTextSpan — macros preset', () {
    testWidgets('highlights {{}} only', (tester) async {
      await tester.pumpWidget(_buildApp());
      final ctrl = StyledTextController(
        text: 'before {{macro}} after',
        preset: StyledTextPreset.macros,
      );
      final span = ctrl.buildTextSpan(
        context: _pumpContext(tester),
        style: const TextStyle(color: Colors.white),
        withComposing: false,
      );
      expect(span.children, hasLength(3));
      final macroChild = span.children![1] as TextSpan;
      expect(macroChild.text, '{{macro}}');
      expect(macroChild.style?.color, const Color(0xFF0D9488));
      ctrl.dispose();
    });

    testWidgets('"" and ** remain uncolored', (tester) async {
      await tester.pumpWidget(_buildApp());
      final ctrl = StyledTextController(
        text: '"dialogue" **action**',
        preset: StyledTextPreset.macros,
      );
      final span = ctrl.buildTextSpan(
        context: _pumpContext(tester),
        style: const TextStyle(color: Colors.white),
        withComposing: false,
      );
      expect(span.children, hasLength(1));
      ctrl.dispose();
    });
  });

  // ── buildTextSpan — prose mixed patterns ──

  group('buildTextSpan — prose mixed patterns', () {
    testWidgets('highlights "", **, and {{}} in mixed text', (tester) async {
      await tester.pumpWidget(_buildApp());
      final ctrl =
          StyledTextController(text: 'She said "hi" *waved* {{system}}');
      final span = ctrl.buildTextSpan(
        context: _pumpContext(tester),
        style: const TextStyle(color: Colors.white),
        withComposing: false,
      );
      expect(span.children, hasLength(6));
      final childrenTexts =
          span.children!.map((c) => (c as TextSpan).text).toList();
      expect(childrenTexts[0], 'She said ');
      expect(childrenTexts[1], '"hi"');
      expect(childrenTexts[2], ' ');
      expect(childrenTexts[3], '*waved*');
      expect(childrenTexts[4], ' ');
      expect(childrenTexts[5], '{{system}}');
      ctrl.dispose();
    });

    testWidgets('empty text returns single TextSpan child', (tester) async {
      await tester.pumpWidget(_buildApp());
      final ctrl = StyledTextController(text: '');
      final span = ctrl.buildTextSpan(
        context: _pumpContext(tester),
        style: const TextStyle(color: Colors.white),
        withComposing: false,
      );
      expect(span.children, hasLength(1));
      ctrl.dispose();
    });

    testWidgets('plain text returns single TextSpan child', (tester) async {
      await tester.pumpWidget(_buildApp());
      final ctrl = StyledTextController(text: 'hello world');
      final span = ctrl.buildTextSpan(
        context: _pumpContext(tester),
        style: const TextStyle(color: Colors.white),
        withComposing: false,
      );
      expect(span.children, hasLength(1));
      expect((span.children![0] as TextSpan).text, 'hello world');
      ctrl.dispose();
    });
  });

  group('buildTextSpan — priority tokenization {{}} > "" > **', () {
    testWidgets('macro inside dialogue keeps macro coloring', (tester) async {
      await tester.pumpWidget(_buildApp());
      final ctrl = StyledTextController(text: '"Hello {{name}}"');
      final span = ctrl.buildTextSpan(
        context: _pumpContext(tester),
        style: const TextStyle(color: Colors.white),
        withComposing: false,
      );
      expect(span.children, hasLength(3));
      final children = span.children!.map((c) => c as TextSpan).toList();
      expect(children[0].text, '"Hello ');
      expect(children[0].style?.color, const Color(0xFFB45309));
      expect(children[1].text, '{{name}}');
      expect(children[1].style?.color, const Color(0xFF0D9488));
      expect(children[2].text, '"');
      expect(children[2].style?.color, const Color(0xFFB45309));
      ctrl.dispose();
    });

    testWidgets('macro inside action keeps macro coloring', (tester) async {
      await tester.pumpWidget(_buildApp());
      final ctrl = StyledTextController(text: '*waves {{name}}*');
      final span = ctrl.buildTextSpan(
        context: _pumpContext(tester),
        style: const TextStyle(color: Colors.white),
        withComposing: false,
      );
      expect(span.children, hasLength(3));
      final children = span.children!.map((c) => c as TextSpan).toList();
      expect(children[0].text, '*waves ');
      expect(children[0].style?.color, const Color(0xFF1565C0));
      expect(children[1].text, '{{name}}');
      expect(children[1].style?.color, const Color(0xFF0D9488));
      expect(children[2].text, '*');
      expect(children[2].style?.color, const Color(0xFF1565C0));
      ctrl.dispose();
    });

    testWidgets('macro and dialogue inside action', (tester) async {
      await tester.pumpWidget(_buildApp());
      final ctrl = StyledTextController(text: '*"{{x}}"*');
      final span = ctrl.buildTextSpan(
        context: _pumpContext(tester),
        style: const TextStyle(color: Colors.white),
        withComposing: false,
      );
      expect(span.children, hasLength(5));
      final children = span.children!.map((c) => c as TextSpan).toList();
      expect(children[0].text, '*');
      expect(children[0].style?.color, const Color(0xFF1565C0));
      expect(children[1].text, '"');
      expect(children[1].style?.color, const Color(0xFFB45309));
      expect(children[2].text, '{{x}}');
      expect(children[2].style?.color, const Color(0xFF0D9488));
      expect(children[3].text, '"');
      expect(children[3].style?.color, const Color(0xFFB45309));
      expect(children[4].text, '*');
      expect(children[4].style?.color, const Color(0xFF1565C0));
      ctrl.dispose();
    });

    testWidgets('macro inside dialogue in mixed text', (tester) async {
      await tester.pumpWidget(_buildApp());
      final ctrl = StyledTextController(
        text: '"He said {{name}}" and *{{verb}}*',
      );
      final span = ctrl.buildTextSpan(
        context: _pumpContext(tester),
        style: const TextStyle(color: Colors.white),
        withComposing: false,
      );
      final childrenTexts =
          span.children!.map((c) => (c as TextSpan).text).toList();
      expect(childrenTexts, [
        '"He said ',
        '{{name}}',
        '"',
        ' and ',
        '*',
        '{{verb}}',
        '*',
      ]);
      ctrl.dispose();
    });

    testWidgets('unclosed macro inside dialogue does not break', (tester) async {
      await tester.pumpWidget(_buildApp());
      final ctrl = StyledTextController(text: '"hello {{name"');
      final span = ctrl.buildTextSpan(
        context: _pumpContext(tester),
        style: const TextStyle(color: Colors.white),
        withComposing: false,
      );
      final childrenTexts =
          span.children!.map((c) => (c as TextSpan).text).toList();
      expect(childrenTexts, ['"hello {{name"']);
      ctrl.dispose();
    });

    testWidgets('* inside "" is literal, does not split action', (tester) async {
      await tester.pumpWidget(_buildApp());
      final ctrl = StyledTextController(text: '*waves "*Hello {{user}}"*');
      final span = ctrl.buildTextSpan(
        context: _pumpContext(tester),
        style: const TextStyle(color: Colors.white),
        withComposing: false,
      );
      final childrenTexts =
          span.children!.map((c) => (c as TextSpan).text).toList();
      expect(childrenTexts, [
        '*waves ',
        '"*Hello ',
        '{{user}}',
        '"',
        '*',
      ]);
      // Verify macro keeps teal regardless of nesting
      final macroChild = span.children!
          .map((c) => c as TextSpan)
          .firstWhere((c) => c.text == '{{user}}');
      expect(macroChild.style?.color, const Color(0xFF0D9488));
      ctrl.dispose();
    });

    testWidgets('* inside "" is just text, no action match', (tester) async {
      await tester.pumpWidget(_buildApp());
      final ctrl = StyledTextController(text: '"hello *world*"');
      final span = ctrl.buildTextSpan(
        context: _pumpContext(tester),
        style: const TextStyle(color: Colors.white),
        withComposing: false,
      );
      final childrenTexts =
          span.children!.map((c) => (c as TextSpan).text).toList();
      // The * inside quotes is just text — the whole thing is one dialogue span
      expect(childrenTexts, ['"hello *world*"']);
      ctrl.dispose();
    });

    testWidgets('" inside {{}} is just text, not dialogue delimiter',
        (tester) async {
      await tester.pumpWidget(_buildApp());
      final ctrl = StyledTextController(text: 'before {{name"value"}} after');
      final span = ctrl.buildTextSpan(
        context: _pumpContext(tester),
        style: const TextStyle(color: Colors.white),
        withComposing: false,
      );
      final childrenTexts =
          span.children!.map((c) => (c as TextSpan).text).toList();
      expect(childrenTexts, ['before ', '{{name"value"}}', ' after']);
      ctrl.dispose();
    });

    testWidgets(
        'dialogue after macro split does not start with " but is still dialogue',
        (tester) async {
      await tester.pumpWidget(_buildApp());
      final ctrl = StyledTextController(
        text:
            '"A special request from the Polish ambassador—for our new President and esteemed chief of staff, {{char}}. \'Nie Bądź Taka\' by Lil\' Wally."',
      );
      final span = ctrl.buildTextSpan(
        context: _pumpContext(tester),
        style: const TextStyle(color: Colors.white),
        withComposing: false,
      );
      final children = span.children!.map((c) => c as TextSpan).toList();
      final childrenTexts = children.map((c) => c.text).toList();
      expect(childrenTexts, [
        '"A special request from the Polish ambassador—for our new President and esteemed chief of staff, ',
        '{{char}}',
        '. \'Nie Bądź Taka\' by Lil\' Wally."',
      ]);
      // The trailing dialogue (does not start with ") must still be amber
      expect(children[0].style?.color, const Color(0xFFB45309));
      expect(children[1].style?.color, const Color(0xFF0D9488));
      expect(children[2].style?.color, const Color(0xFFB45309));
      ctrl.dispose();
    });

    testWidgets(
        'two macros in one dialogue — middle split does not start or end with delimiter',
        (tester) async {
      await tester.pumpWidget(_buildApp());
      final ctrl = StyledTextController(
        text: '"hello {{x}} middle {{y}} world."',
      );
      final span = ctrl.buildTextSpan(
        context: _pumpContext(tester),
        style: const TextStyle(color: Colors.white),
        withComposing: false,
      );
      final children = span.children!.map((c) => c as TextSpan).toList();
      final childrenTexts = children.map((c) => c.text).toList();
      expect(childrenTexts, [
        '"hello ',
        '{{x}}',
        ' middle ',
        '{{y}}',
        ' world."',
      ]);
      // Middle segment " middle " is dialogue despite no " at either edge
      expect(children[2].style?.color, const Color(0xFFB45309));
      ctrl.dispose();
    });

    testWidgets('action after macro+dialogue split does not start with *',
        (tester) async {
      await tester.pumpWidget(_buildApp());
      final ctrl = StyledTextController(
        text: '*"{{x}}" and {{y}}*',
      );
      final span = ctrl.buildTextSpan(
        context: _pumpContext(tester),
        style: const TextStyle(color: Colors.white),
        withComposing: false,
      );
      final children = span.children!.map((c) => c as TextSpan).toList();
      final childrenTexts = children.map((c) => c.text).toList();
      expect(childrenTexts, [
        '*',
        '"',
        '{{x}}',
        '"',
        ' and ',
        '{{y}}',
        '*',
      ]);
      // The tail action " and {{y}}" — the split before {{y}} starts with ' and '
      // which is not *, yet must be action-colored
      final actionChild =
          children.firstWhere((c) => c.text == ' and ');
      expect(actionChild.style?.color, const Color(0xFF1565C0));
      ctrl.dispose();
    });
  });

  // ── Lifecycle & spell check (with method channel mock) ──

  group('StyledTextController lifecycle & spell check', () {
    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('front_porch_ai/spell_check'),
        (MethodCall methodCall) async {
          if (methodCall.method != 'spellCheck') return null;
          final args = methodCall.arguments as List<dynamic>;
          final text = args[1] as String;
          final idx = text.indexOf('misspelled');
          if (idx == -1) return <Map<String, dynamic>>[];
          return <Map<String, dynamic>>[
            {
              'startIndex': idx,
              'endIndex': idx + 10,
              'suggestions': ['correct', 'fixed'],
            },
          ];
        },
      );
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('front_porch_ai/spell_check'),
        null,
      );
    });

    testWidgets('dispose cancels pending spell check', (tester) async {
      await tester.pumpWidget(_buildApp());
      final ctrl = StyledTextController()..text = 'misspelled word';
      ctrl.dispose();
      await tester.pump(const Duration(milliseconds: 300));
      expect(ctrl.spellCheckResults, isNull);
    });

    testWidgets('debounce fires spell check after 300ms', (tester) async {
      await tester.pumpWidget(_buildApp());
      final ctrl = StyledTextController()..text = 'misspelled word';

      await tester.pump(const Duration(milliseconds: 200));
      expect(ctrl.spellCheckResults, isNull);

      await tester.pump(const Duration(milliseconds: 100));
      expect(ctrl.spellCheckResults, isNotNull);
      ctrl.dispose();
    });

    testWidgets('populates results for misspelled text', (tester) async {
      await tester.pumpWidget(_buildApp());
      final ctrl = StyledTextController()..text = 'this is misspelled';

      await tester.pump(const Duration(milliseconds: 300));
      final results = ctrl.spellCheckResults;
      expect(results, isNotNull);
      expect(results!.suggestionSpans, hasLength(1));
      expect(results.suggestionSpans[0].suggestions, ['correct', 'fixed']);
      ctrl.dispose();
    });

    testWidgets('returns null for correctly spelled text', (tester) async {
      await tester.pumpWidget(_buildApp());
      final ctrl = StyledTextController()..text = 'hello world';

      await tester.pump(const Duration(milliseconds: 300));
      expect(ctrl.spellCheckResults, isNull);
      ctrl.dispose();
    });
  });

  // ── tokenizeChat — localized / typographic dialogue quotes (#95) ──

  group('tokenizeChat localized dialogue quotes', () {
    List<String> dialogues(String text) => tokenizeChat(text)
        .where((t) => t.type == StyledTokenType.dialogue)
        .map((t) => t.matchText)
        .toList();

    test('straight double quotes still work (regression)', () {
      expect(dialogues('He said "hello" today'), ['"hello"']);
    });

    test('English typographic “…”', () {
      expect(dialogues('He said “hello” today'), ['“hello”']);
    });

    test('German „…“', () {
      expect(dialogues('Er sagte „Hallo“ heute'), ['„Hallo“']);
    });

    test('German/Polish „…” (curly-close variant)', () {
      expect(dialogues('„Cześć”'), ['„Cześć”']);
    });

    test('French/Italian/Spanish guillemets «…»', () {
      expect(dialogues('Il a dit «Bonjour» hier'), ['«Bonjour»']);
    });

    test('German-alt / Danish guillemets »…«', () {
      expect(dialogues('Er sagte »Hallo« heute'), ['»Hallo«']);
    });

    test('Nordic ”…”', () {
      expect(dialogues('Han sa ”Hej” idag'), ['”Hej”']);
    });

    test('Japanese / CJK 「…」', () {
      expect(dialogues('彼は「こんにちは」と言った'), ['「こんにちは」']);
    });

    test('localized dialogue coexists with *action*', () {
      final tokens = tokenizeChat('„Hallo“ *winkt*');
      final dlg = tokens
          .where((t) => t.type == StyledTokenType.dialogue)
          .map((t) => t.matchText)
          .toList();
      final act = tokens
          .where((t) => t.type == StyledTokenType.action)
          .map((t) => t.matchText)
          .toList();
      expect(dlg, ['„Hallo“']);
      expect(act, ['*winkt*']);
    });

    test('scanDialogue finds a guillemet range at the right offsets', () {
      final ranges = scanDialogue('«Bonjour»', const []);
      expect(ranges, hasLength(1));
      expect(ranges.first.start, 0);
      expect(ranges.first.end, '«Bonjour»'.length);
    });
  });
}
