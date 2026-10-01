// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The phone's base list (web_ui civitaiBases.ts) is the desktop's, choice for
// choice and in the same order, including what a choice for several sends.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/image/civitai_bases.dart';

void main() {
  test('the web base list is the desktop one', () {
    final ts = File(
      'web_ui/src/components/models/civitaiBases.ts',
    ).readAsStringSync();
    final list = ts.substring(
      ts.indexOf('civitaiBaseGroups: CivitaiBaseGroup[] = ['),
      ts.indexOf('/** What a choice sends'),
    );
    String unquote(String s) => s.replaceAll(r"\'", "'");
    final web = <String>[];
    for (final m in RegExp(
      r"title: '((?:[^'\\]|\\.)*)'|label: '((?:[^'\\]|\\.)*)',\s*api: '((?:[^'\\]|\\.)*)'(?:,\s*several: \[([^\]]*)\])?",
    ).allMatches(list)) {
      if (m.group(1) != null) {
        web.add('group ${unquote(m.group(1)!)}');
        continue;
      }
      final several = m.group(4) == null
          ? ''
          : RegExp(
              r"'([^']*)'",
            ).allMatches(m.group(4)!).map((s) => s.group(1)).join('|');
      web.add('${unquote(m.group(2)!)} = ${unquote(m.group(3)!)} [$several]');
    }
    final dart = [
      for (final group in kCivitaiBaseGroups) ...[
        'group ${group.title}',
        for (final choice in group.choices)
          '${choice.label} = ${choice.api} [${choice.several.join('|')}]',
      ],
    ];
    expect(web, dart);
    expect(web, contains(startsWith('Flux.2 Klein (all) = ')));
  });
}
