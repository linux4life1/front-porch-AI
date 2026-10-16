// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// The creator's template library on a real folder: save, list, rename and
// delete; files that cannot be read; the merge that keeps the other
// surface's keys; the built-ins; and the name rules both surfaces read from
// one fixture.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/services/chargen/chargen.dart';

final Map<String, dynamic> _vectors =
    jsonDecode(
          File(
            'test/fixtures/chargen/creator_template_vectors.json',
          ).readAsStringSync(),
        )
        as Map<String, dynamic>;

List<Map<String, dynamic>> _rows(String key) => [
  for (final row in _vectors[key] as List) row as Map<String, dynamic>,
];

Matcher _refused(int status, {String? reason, String? message}) {
  var m = isA<TemplateRefused>().having((e) => e.status, 'status', status);
  if (reason != null) m = m.having((e) => e.reason, 'reason', reason);
  if (message != null) m = m.having((e) => e.message, 'message', message);
  return m;
}

void main() {
  late Directory root;
  late ChargenTemplateLibrary library;

  setUp(() {
    root = Directory.systemTemp.createTempSync('fpai templates');
    library = ChargenTemplateLibrary.under(root.path)!;
  });

  tearDown(() => root.deleteSync(recursive: true));

  File file(String name) => File(p.join(chargenTemplatesDir(root.path), name));

  Map<String, dynamic> stored(String slug) =>
      jsonDecode(file('$slug.json').readAsStringSync()) as Map<String, dynamic>;

  test('save, list newest first, replace, rename moves the file, '
      'delete', () async {
    expect(ChargenTemplateLibrary.under(null), isNull);
    expect(await library.listMine(), isEmpty, reason: 'no folder yet');

    var saved = await library.save('Harbor town, slow burn', {
      'mode': 'guided',
    }, now: DateTime.utc(2026, 10, 1));
    expect(saved.replaced, isFalse);
    expect(saved.template.slug, 'harbor-town-slow-burn');
    expect(file('harbor-town-slow-burn.json').existsSync(), isTrue);
    await library.save('  Modern 18+ quick ', {
      'mode': 'quick',
      'nsfw': true,
    }, now: DateTime.utc(2026, 10, 2));
    expect(
      [for (final t in await library.listMine()) t.name],
      ['Modern 18+ quick', 'Harbor town, slow burn'],
    );

    saved = await library.save('Harbor town, slow burn', {
      'narrativeTense': 'past',
    }, now: DateTime.utc(2026, 10, 3));
    expect(saved.replaced, isTrue);
    final mine = await library.listMine();
    expect(
      [for (final t in mine) t.slug],
      ['harbor-town-slow-burn', 'modern-18-quick'],
    );
    expect(mine.first.savedAt, DateTime.utc(2026, 10, 3));
    expect(mine.first.form.text('narrativeTense'), 'past');
    expect(
      mine.first.form.text('mode'),
      'guided',
      reason: 'the replace kept what the stored file had',
    );

    final renamed = await library.rename('modern-18-quick', 'Modern quick');
    expect(renamed.slug, 'modern-quick');
    expect(file('modern-18-quick.json').existsSync(), isFalse);
    expect(stored('modern-quick')['name'], 'Modern quick');
    expect(renamed.savedAt, DateTime.utc(2026, 10, 2), reason: 'not a save');
    expect(renamed.form.flag('nsfw'), isTrue);

    await expectLater(
      library.rename('modern-quick', 'Harbor Town  Slow Burn'),
      throwsA(_refused(409, reason: 'taken', message: kTemplateTakenProblem)),
    );
    await expectLater(
      library.rename('nowhere', 'Anything'),
      throwsA(_refused(404)),
    );

    await library.delete('modern-quick');
    expect(file('modern-quick.json').existsSync(), isFalse);
    await expectLater(library.delete('modern-quick'), throwsA(_refused(404)));

    final all = await library.list();
    expect(all, hasLength(1 + kBuiltInTemplates.length));
    expect(
      [for (final t in all.take(3)) t.name],
      ['Harbor town, slow burn', 'Tsundere', 'Kuudere'],
    );
  });

  test(
    'files that cannot be read are listed as broken, never thrown',
    () async {
      await library.save('Good one', {
        'mode': 'quick',
      }, now: DateTime.utc(2026, 10, 4));
      file('bad.json').writeAsStringSync('{"name": "Bad", "form": {');
      file('array.json').writeAsStringSync('[1, 2, 3]');
      Directory(file('x.json').path).createSync();
      file('nameless.json').writeAsStringSync(
        jsonEncode({
          'form': {'mode': 'guided'},
        }),
      );
      file(
        'tsundere.json',
      ).writeAsStringSync(jsonEncode({'name': 'Tsundere', 'form': {}}));
      file('notes.txt').writeAsStringSync('not a template');
      file('half.json.tmp').writeAsStringSync('{');

      final mine = await library.listMine();
      expect(
        [for (final t in mine) t.slug],
        ['good-one', 'array', 'bad', 'nameless', 'x'],
        reason: 'the built-in owns tsundere; other files are not templates',
      );
      expect(mine.first.broken, isFalse);
      for (final t in mine.skip(1)) {
        expect(t.broken, isTrue, reason: t.slug);
        expect(t.problem, kTemplateUnreadable);
        expect(templateSummaryLine(t), kTemplateUnreadable);
        expect(t.toJson()['broken'], isTrue);
      }
      for (final json in <Object?>[
        null,
        42,
        '{"name": 3}',
        '{"name": "A", '
            '"form": []}',
      ]) {
        expect(
          CreatorTemplate.fromFile('a', json).broken,
          isTrue,
          reason: '$json',
        );
      }
      expect((await library.read('bad'))?.broken, isTrue);
      expect(await library.read('tsundere'), isNull);
      expect(await library.read('../outside'), isNull);
      await expectLater(
        library.rename('bad', 'Fixed'),
        throwsA(_refused(409, reason: 'broken')),
      );

      final saved = await library.save('Bad', {'mode': 'guided'});
      expect(saved.replaced, isTrue);
      expect(saved.template.broken, isFalse);
      for (final slug in ['array', 'nameless', 'x']) {
        await library.delete(slug);
      }
      expect(Directory(file('x.json').path).existsSync(), isFalse);
      expect([for (final t in await library.listMine()) t.slug]..sort(), [
        'bad',
        'good-one',
      ]);
    },
  );

  test('a save keeps keys the form does not carry, basedOn carries them to '
      'a new name, and the name is never stored', () async {
    // The desktop's save: its own key, a key from a newer app, and the
    // character's name, which a template never keeps.
    await library.save('Harbor', {
      'mode': 'guided',
      'artStyle': 'Painterly',
      'fromANewerApp': {'x': 1},
      'name': 'Aria Vale',
    });
    // The phone saves the same template with none of the desktop's keys.
    await library.save('Harbor', {
      'mode': 'quick',
      'quickKeywords': 'salt, rope',
      'name': 'Bo',
    });
    final onDisk = stored('harbor');
    expect(onDisk['name'], 'Harbor');
    expect(onDisk['version'], kTemplateFormVersion);
    final form = onDisk['form'] as Map<String, dynamic>;
    expect(form['mode'], 'quick');
    expect(form['quickKeywords'], 'salt, rope');
    expect(form['artStyle'], 'Painterly');
    expect(form['fromANewerApp'], {'x': 1});
    expect(form.containsKey('name'), isFalse);

    final copy = await library.save('Harbor, phone edit', {
      'nsfw': true,
    }, basedOn: 'harbor');
    expect(copy.replaced, isFalse);
    expect(copy.template.form['artStyle'], 'Painterly');
    expect(copy.template.form['fromANewerApp'], {'x': 1});
    expect(copy.template.form['mode'], 'quick');
    expect(copy.template.form['nsfw'], isTrue);

    final fromBuiltIn = await library.save('My tsundere', {
      'nsfw': true,
    }, basedOn: 'tsundere');
    expect(fromBuiltIn.template.form['archetype'], 'Tsundere');
    expect(
      fromBuiltIn.template.form['automatedConcept'],
      kArchetypePresets['Tsundere']?['concept'],
    );

    expect(
      mergeTemplateForms([
        null,
        {'a': 1, 'b': 1, 'name': 'x'},
        {'b': 2},
      ]),
      {'a': 1, 'b': 2},
    );
  });

  test('two saves at once, from two libraries on one folder, keep both '
      'sets of keys', () async {
    final relay = ChargenTemplateLibrary.under(root.path)!;
    await Future.wait([
      library.save('Shared', {'artStyle': 'Painterly'}),
      relay.save('Shared', {'quickKeywords': 'salt'}),
    ]);
    final form = stored('shared')['form'] as Map<String, dynamic>;
    expect(form['artStyle'], 'Painterly');
    expect(form['quickKeywords'], 'salt');
  });

  test('a form value that is absent, of the wrong type or outside its '
      'options reads as the default', () {
    final form = <String, Object?>{
      'mode': 'Guided',
      'nsfw': 'yes',
      'altGreetingCount': 9,
      'greetingTones': 'Neutral',
      'sex': 3,
      'loreDepth': 'Deep',
      'notableFeatures': ['Freckles', 7],
      'interviewQuestions': [
        {'key': 'voice'},
      ],
    };
    expect(form.text('mode'), 'automated');
    expect(form.flag('nsfw'), isFalse);
    expect(form.flag('generateLorebook'), isTrue);
    expect(form.count('altGreetingCount'), 2);
    expect(
      <String, Object?>{'altGreetingCount': 4.0}.count('altGreetingCount'),
      4,
    );
    expect(form.words('greetingTones'), ['Neutral']);
    expect(form.text('sex'), '');
    expect(form.text('loreDepth'), 'Deep');
    expect(form.words('notableFeatures'), ['Freckles']);
    expect(form.interview()?.single.key, 'voice');
    expect(<String, Object?>{}.interview(), isNull);
    final defaults = templateDefaults();
    expect(defaults.keys, [for (final f in kTemplateFields) f.key]);
    expect(defaults.keys.toSet(), hasLength(kTemplateFields.length));
  });

  test('a link in the folder is neither listed nor read, and a save replaces '
      'an empty folder in its place', () async {
    await library.save('Mine', {'mode': 'quick'});
    // A link to a file outside the folder, named like a template.
    final outside = File(p.join(root.path, 'outside.json'))
      ..writeAsStringSync(jsonEncode(stored('mine')));
    await Link(file('outside.json').path).create(outside.path);
    expect((await library.listMine()).map((t) => t.slug), ['mine']);
    expect(await library.read('outside'), isNull);

    Directory(file('harbor.json').path).createSync();
    final listed = await library.listMine();
    expect(listed.singleWhere((t) => t.slug == 'harbor').broken, isTrue);
    await library.save('Harbor', {'mode': 'guided'});
    expect((await library.read('harbor'))?.form['mode'], 'guided');
    expect(file('harbor.json').existsSync(), isTrue);
    for (final left in ['harbor.json.bak', 'harbor.json.tmp']) {
      expect(
        FileSystemEntity.typeSync(file(left).path),
        FileSystemEntityType.notFound,
        reason: left,
      );
    }
  }, skip: Platform.isWindows ? 'making a link needs a privilege' : false);

  test('a replace that fails leaves the old copy in place and the new bytes '
      'in the temp file', () async {
    // A folder in the file's place that cannot move aside, because a folder
    // with something in it already holds the aside name.
    Directory(file('harbor.json').path).createSync(recursive: true);
    Directory(file('harbor.json.bak').path).createSync();
    File(p.join(file('harbor.json.bak').path, 'keep')).writeAsStringSync('');
    await expectLater(
      library.save('Harbor', {'mode': 'guided'}),
      throwsA(isA<FileSystemException>()),
    );
    expect(Directory(file('harbor.json').path).existsSync(), isTrue);
    final temp = jsonDecode(file('harbor.json.tmp').readAsStringSync());
    expect((temp as Map)['form'], {'mode': 'guided'});
  });

  group('the vectors both surfaces read', () {
    test('slugs', () {
      for (final v in _rows('slugs')) {
        expect(templateSlug(v['name'] as String), v['slug'], reason: v['name']);
      }
    });

    test('name problems and captions', () {
      for (final v in _rows('problems')) {
        expect(
          templateNameProblem(v['name'] as String),
          v['problem'],
          reason: '"${v['name']}"',
        );
      }
      expect(kTemplateTakenProblem, _vectors['takenProblem']);
      expect(kTemplateReplacesCaption, _vectors['replacesCaption']);
    });

    test('summary lines', () {
      for (final v in _rows('summaryLines')) {
        final t = CreatorTemplate(
          slug: 'v',
          name: 'v',
          form: (v['form'] as Map).cast<String, Object?>(),
        );
        expect(templateSummaryLine(t), v['desktop']);
        expect(templateSummaryLine(t, phone: true), v['phone']);
      }
    });

    test('saved labels', () {
      for (final v in _rows('savedLabels')) {
        expect(
          templateSavedLabel(
            DateTime.parse(v['savedAt'] as String),
            now: DateTime.parse(v['now'] as String),
          ),
          v['label'],
        );
      }
    });

    test('the built-ins: counted against the label, featured first', () {
      expect(kBuiltInTemplates, hasLength(_vectors['builtInCount']));
      expect(kAllBuiltInLabel, _vectors['builtInLabel']);
      expect([
        for (final t in kBuiltInTemplates.take(2)) t.name,
      ], _vectors['featured']);
    });
  });

  test('built-ins: every archetype, read-only, refused on save, rename and '
      'delete', () async {
    expect(
      [for (final t in kBuiltInTemplates) t.name],
      [
        'Tsundere',
        'Kuudere',
        for (final n in kArchetypePresets.keys)
          if (n != 'Tsundere' && n != 'Kuudere') n,
      ],
    );
    final darkLord = builtInTemplate('dark-lord');
    expect(darkLord?.builtIn, isTrue);
    expect(darkLord?.form.keys, containsAll(templateDefaults().keys));
    expect(darkLord?.form['mode'], 'automated');
    expect(darkLord?.form['archetype'], 'Dark Lord');
    expect(
      darkLord?.form['automatedConcept'],
      kArchetypePresets['Dark Lord']?['concept'],
    );
    expect(
      darkLord?.form['automatedKeywords'],
      kArchetypePresets['Dark Lord']?['keywords'],
    );
    expect(darkLord?.form['greetingTones'], ['Neutral']);
    final tsundere = builtInTemplate('tsundere')!;
    expect(
      tsundere.summary.blurb,
      'sharp-tongued, secretly caring, stubborn, easily flustered',
    );
    expect(
      templateSummaryLine(tsundere),
      'Automated · sharp-tongued, secretly caring',
    );
    expect(
      templateSummaryLine(tsundere, phone: true),
      'Automated · sharp-tongued',
    );
    expect(
      templateSummaryLine(builtInTemplate('femme-fatale')!),
      'Automated · seductive, cunning',
    );

    await expectLater(
      library.save('Tsundere', {}),
      throwsA(_refused(409, reason: 'builtIn')),
    );
    await expectLater(
      library.save('femme  FATALE', {}),
      throwsA(_refused(409, reason: 'builtIn')),
    );
    await expectLater(library.save('   ', {}), throwsA(_refused(400)));
    await expectLater(
      library.rename('kuudere', 'Mine'),
      throwsA(_refused(409, reason: 'builtIn')),
    );
    await library.save('Mine', {});
    await expectLater(
      library.rename('mine', 'Kuudere'),
      throwsA(_refused(409, reason: 'builtIn')),
    );
    await expectLater(
      library.delete('tsundere'),
      throwsA(_refused(409, reason: 'builtIn')),
    );
    expect(
      [
        for (final e in Directory(chargenTemplatesDir(root.path)).listSync())
          p.basename(e.path),
      ],
      ['mine.json'],
    );
  });

  test('every key the phone shows is mapped in its template form', () {
    final source = File('web_ui/src/components/aichargen/templateForm.ts');
    expect(source.existsSync(), isTrue, reason: '${source.path} is missing');
    final text = source.readAsStringSync();
    final missing = [
      for (final f in kTemplateFields)
        if (f.onPhone &&
            !RegExp('(?<![A-Za-z0-9_])${f.key}(?![A-Za-z0-9_])').hasMatch(text))
          f.key,
    ];
    expect(missing, isEmpty);
  });
}
