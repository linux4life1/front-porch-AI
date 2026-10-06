// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// The ratchet behind the hygiene guards that count a banned form per file
// (test/hygiene/raw_*_ratchet_test.dart). It compares a census (file -> hits)
// with a recorded baseline (file -> count): a file may never go above its
// count, and a file that is not in the baseline must have none.

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'dart_source.dart';

export 'dart_source.dart';

/// Every `.dart` file under [root], as a forward-slash path.
List<String> dartFiles(String root) =>
    Directory(root)
        .listSync(recursive: true)
        .whereType<File>()
        .map((f) => f.path.replaceAll('\\', '/'))
        .where((path) => path.endsWith('.dart'))
        .toList()
      ..sort();

/// Reads a ratchet baseline (path -> count). It must exist, be sorted by path
/// so diffs stay readable, and hold only positive counts.
Map<String, int> readBaseline(String baselinePath) {
  final file = File(baselinePath);
  if (!file.existsSync()) {
    throw StateError(
      '$baselinePath is missing. It must never be deleted: an empty {} '
      'means "no offenders left", absence means the ratchet is gone.',
    );
  }
  final baseline = (jsonDecode(file.readAsStringSync()) as Map).map(
    (k, v) => MapEntry(k as String, (v as num).toInt()),
  );
  final keys = baseline.keys.toList();
  for (var i = 1; i < keys.length; i++) {
    if (keys[i - 1].compareTo(keys[i]) >= 0) {
      throw StateError(
        '$baselinePath must be sorted by path with no duplicates: '
        '"${keys[i]}" comes after "${keys[i - 1]}".',
      );
    }
  }
  for (final MapEntry(:key, :value) in baseline.entries) {
    if (value <= 0) {
      throw StateError('$baselinePath: $key is $value. Drop the entry.');
    }
  }
  return baseline;
}

/// What breaks the ratchet: a file above its recorded count, or a file
/// outside the baseline with any hit. [advice] says how to fix one hit.
List<String> ratchetProblems({
  required Map<String, int> baseline,
  required Map<String, List<RatchetHit>> census,
  required String baselinePath,
  required String noun,
  required String Function(RatchetHit hit) advice,
  required String fix,
}) {
  final problems = <String>[];
  String listed(List<RatchetHit> hits) =>
      hits.map((h) => '  $h\n      -> ${advice(h)}').join('\n');
  census.forEach((path, hits) {
    final allowed = baseline[path];
    if (allowed == null && hits.isNotEmpty) {
      problems.add(
        '$path is not in $baselinePath, so it must have no $noun. '
        'It has ${hits.length}:\n${listed(hits)}\n'
        'If this file was split or renamed out of a file in the baseline, '
        'move that count to the new path in the same change (a baseline '
        'edit needs the maintainer\'s approved-test-change label).',
      );
    } else if (allowed != null && hits.length > allowed) {
      problems.add(
        '$path has ${hits.length} $noun; the baseline allows $allowed. '
        'The new ones are among these:\n${listed(hits)}',
      );
    }
  });
  if (problems.isNotEmpty) problems.add(fix);
  return problems;
}

/// With FPAI_TIGHTEN_BASELINES=1, lowers each entry of [baselinePath] to what
/// the tree has now and drops clean or deleted files. It never raises an
/// entry or adds one, so the baseline can only shrink.
void tightenBaselineIfAsked(
  String baselinePath,
  Map<String, int> baseline,
  Map<String, List<RatchetHit>> census,
) {
  if (Platform.environment['FPAI_TIGHTEN_BASELINES'] != '1') return;
  final tightened = <String, int>{
    for (final MapEntry(:key, :value) in baseline.entries)
      if ((census[key]?.length ?? 0) > 0) key: min(census[key]!.length, value),
  };
  final json = const JsonEncoder.withIndent('  ').convert(tightened);
  File(baselinePath).writeAsStringSync('$json\n');
  // ignore: avoid_print
  print(
    'Tightened $baselinePath: ${baseline.length} -> ${tightened.length} '
    'files, ${baseline.values.fold(0, (a, b) => a + b)} -> '
    '${tightened.values.fold(0, (a, b) => a + b)} hits.',
  );
}
