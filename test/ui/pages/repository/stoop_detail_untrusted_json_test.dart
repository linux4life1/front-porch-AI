// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

// The Stoop detail panel renders JSON a STRANGER uploaded. `someString as
// List?` throws a TypeError in Dart — it does not evaluate to null — so a card
// whose "alternate_greetings" or member list came back as a string or an object
// takes down the entire slide-in panel (red box in debug, blank in release) and
// that card can never be viewed or downloaded. `is List` omits the section
// instead. Same rule, and the same wording, as stoop_identity_sections.dart:41,
// which was hardened after Grok caught it in review on 2026-08-07.
//
// The panel is a private StatefulWidget that fetches over HTTP in initState, so
// there is no seam to pump a malformed card through; this reads the file the
// way chaos_global_toggle_test reads its call sites.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the Stoop detail panel never casts untrusted card JSON with as List', () {
    final src = File(
      'lib/ui/pages/repository/stoop_card_detail_page.dart',
    ).readAsStringSync();

    final offenders = <String>[
      for (final line in src.split('\n'))
        if (RegExp(r'as List\??').hasMatch(line) && !line.trimLeft().startsWith('//'))
          line.trim(),
    ];
    expect(
      offenders,
      isEmpty,
      reason: 'a wrong-typed field in a stranger\'s card would throw here and '
          'blank the whole detail panel — use `is List` and omit the section',
    );

    // The two fields that carry lists must be read defensively.
    expect(src, contains("final raw = d.card['alternate_greetings'];"));
    expect(src, contains('raw is List ? raw : const []'));
    expect(src, contains('rawMembers is List'));
  });
}
