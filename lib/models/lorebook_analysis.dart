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

import 'package:front_porch_ai/models/lorebook.dart';
import 'package:front_porch_ai/models/lorebook_codec.dart';

/// Pure analysis of a decoded lorebook for the import wizard's review step:
/// what format it is, what features it uses, roughly how big it is, and
/// anything worth warning about. No widgets, fully unit-testable.
class LorebookImportSummary {
  final LorebookFormat format;
  final String suggestedName;
  final String suggestedDescription;
  final int entryCount;
  final int enabledCount;
  final int approxTokens;

  /// Feature label → count of entries using it. Only non-zero features.
  final Map<String, int> features;

  final List<String> warnings;

  const LorebookImportSummary({
    required this.format,
    required this.suggestedName,
    required this.suggestedDescription,
    required this.entryCount,
    required this.enabledCount,
    required this.approxTokens,
    required this.features,
    required this.warnings,
  });

  /// Friendly format label for the review banner.
  String get formatLabel => switch (format) {
        LorebookFormat.novelAi => 'NovelAI lorebook',
        LorebookFormat.agnai => 'AgnAI memory book',
        LorebookFormat.risu => 'RisuAI lorebook',
        LorebookFormat.v3Lorebook => 'Character Card V3 lorebook',
        LorebookFormat.fpaiOrSt => 'SillyTavern / Chub / Front Porch',
      };

  static LorebookImportSummary analyze(
    Map<String, dynamic> rawJson,
    Lorebook book,
  ) {
    var chars = 0;
    var secondary = 0;
    var chance = 0;
    var regex = 0;
    var timers = 0;
    var groups = 0;
    var positioned = 0;
    var recursionCtl = 0;
    var alwaysOn = 0;
    var vectorized = 0;
    var enabled = 0;

    for (final e in book.entries) {
      chars += e.content.length;
      if (e.enabled) enabled++;
      if (e.secondaryKeys.isNotEmpty && e.selective) secondary++;
      if (e.useProbability && e.probability < 100) chance++;
      if (e.useRegex || e.keys.any((k) => k.startsWith('/'))) regex++;
      if (e.sticky > 0 || e.cooldown > 0 || e.delay > 0) timers++;
      if (e.group.trim().isNotEmpty) groups++;
      if (e.position != 0 && e.position != 7) positioned++;
      if (e.excludeRecursion || e.preventRecursion || e.delayUntilRecursion > 0) {
        recursionCtl++;
      }
      if (e.constant) alwaysOn++;
      if (e.vectorized) vectorized++;
    }

    final features = <String, int>{
      if (secondary > 0) 'conditional triggers': secondary,
      if (chance > 0) 'chance-based': chance,
      if (regex > 0) 'regex keys': regex,
      if (timers > 0) 'timed': timers,
      if (groups > 0) 'variety groups': groups,
      if (positioned > 0) 'custom placement': positioned,
      if (recursionCtl > 0) 'chain rules': recursionCtl,
      if (alwaysOn > 0) 'always active': alwaysOn,
    };

    final warnings = <String>[];
    if (book.entries.isEmpty) {
      warnings.add('No entries were found in this file.');
    }
    if (enabled < book.entries.length) {
      warnings.add(
        '${book.entries.length - enabled} entries are disabled and will '
        'import disabled.',
      );
    }
    if (vectorized > 0) {
      warnings.add(
        '$vectorized entries use semantic (vector) triggering, which is not '
        'active yet — they import intact and behave as keyword entries.',
      );
    }
    if (book.scanDepth != null ||
        book.tokenBudget != null ||
        book.recursiveScanning != null) {
      warnings.add(
        'This book carries its own scan/budget settings — they override the '
        'global defaults for its entries.',
      );
    }

    return LorebookImportSummary(
      format: detectLorebookFormat(rawJson),
      suggestedName: rawJson['name']?.toString().trim().isNotEmpty == true
          ? rawJson['name'].toString().trim()
          : 'Imported Lorebook',
      suggestedDescription: rawJson['description']?.toString() ?? '',
      entryCount: book.entries.length,
      enabledCount: enabled,
      approxTokens: (chars / 4).ceil(),
      features: features,
      warnings: warnings,
    );
  }
}
