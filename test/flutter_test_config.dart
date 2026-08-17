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

// flutter_test auto-discovers this file and runs [testExecutable] around every
// test in the package. We use it to make widget goldens deterministic:
//   * google_fonts must never hit the network in tests (it would fall back to
//     the Ahem box font and render differently than production);
//   * a real, committed font (Roboto) is loaded so text in widget goldens has
//     stable, cross-run glyph metrics.
// Pure logic / text-JSON golden tests are unaffected by this setup.

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Forbid any runtime font fetch; widget goldens rely solely on the bundled
  // font loaded below.
  GoogleFonts.config.allowRuntimeFetching = false;

  await _loadFont('Roboto', const [
    'test/golden/fonts/Roboto-Regular.ttf',
    'test/golden/fonts/Roboto-Bold.ttf',
  ]);
  // StoopCollapsible titles use GoogleFonts.fraunces (stoopDisplay). Tests
  // forbid runtime fetch, so register the bundled face under the family
  // names google_fonts asks for — otherwise the title paints as a tofu bar.
  await _loadFont('Fraunces', const [
    'test/golden/fonts/Fraunces-SemiBold.ttf',
  ]);
  await _loadFont('Fraunces-SemiBold', const [
    'test/golden/fonts/Fraunces-SemiBold.ttf',
  ]);

  await testMain();
}

Future<void> _loadFont(String family, List<String> paths) async {
  final loader = FontLoader(family);
  for (final path in paths) {
    final file = File(path);
    if (file.existsSync()) {
      loader.addFont(
        Future.value(file.readAsBytesSync().buffer.asByteData()),
      );
    }
  }
  await loader.load();
}
