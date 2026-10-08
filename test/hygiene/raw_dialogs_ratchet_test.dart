// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// Dialogs go through the warm-porch primitives. showWarmDialog
// (lib/ui/widgets/warm_dialog.dart) exists because hand-rolled dialogs left
// the app with a dozen mismatched, dark-only boxes. Every dialog opened any
// other way, anywhere in lib/, is drift from the one warm-porch look.
//
// "Any other way" is every modal Flutter's material, cupertino and widgets
// libraries open, generic or not: showDialog, showModalBottomSheet,
// showGeneralDialog, showAdaptiveDialog, showRawDialog, showCupertinoDialog,
// showCupertinoModalPopup, showCupertinoSheet, showBottomSheet,
// showAboutDialog, showAdaptiveAboutDialog, their routes, and the AlertDialog
// / SimpleDialog / CupertinoAlertDialog widgets. A bare `Dialog(` shell is not
// counted: it cannot open itself, and the call that shows it is. Date and
// time pickers are not counted: there is no warm picker to send them to.
// Deliberately not matched, because nobody writes them by accident: a
// tear-off called through `.call(` or `.new(`, and a dialog built inside
// string interpolation.
//
// When this guard landed lib/ had a few hundred of these, so it is a ratchet
// over test/baselines/raw_dialogs.json (file -> count). A file may never go
// above its count; a file not listed must have none. Converting a dialog
// fails nothing. To lock the progress in, run this test with
// FPAI_TIGHTEN_BASELINES=1: it lowers the counts and can never raise them.

import 'package:flutter_test/flutter_test.dart';

import '../helpers/source_ratchet.dart';

const _baselinePath = 'test/baselines/raw_dialogs.json';
const _primitive = 'lib/ui/widgets/warm_dialog.dart';

final _rawDialog = RegExp(
  r'\b(?:showDialog|showModalBottomSheet|showGeneralDialog|showAdaptiveDialog'
  r'|showRawDialog|showCupertinoDialog|showCupertinoModalPopup'
  r'|showCupertinoSheet|showBottomSheet|showAboutDialog|showAdaptiveAboutDialog'
  r'|DialogRoute|RawDialogRoute|CupertinoDialogRoute|ModalBottomSheetRoute'
  r'|CupertinoModalPopupRoute|CupertinoSheetRoute)'
  r'\s*[<(]'
  r'|\b(?:AlertDialog|SimpleDialog|CupertinoAlertDialog)\s*'
  r'(?:\.\s*adaptive\s*)?\(',
);

Map<String, List<RatchetHit>> _census() => {
  for (final path in dartFiles('lib'))
    if (path != _primitive && !path.endsWith('.g.dart'))
      path: DartSource.read(path).hits(_rawDialog),
}..removeWhere((_, hits) => hits.isEmpty);

String _advice(RatchetHit hit) => hit.match.contains('BottomSheet')
    ? 'a sheet: use showWarmDialog, or add a warm sheet to $_primitive'
    : 'use showWarmDialog(context, title: ..., content: ..., actions: [...])';

void main() {
  test('no new raw dialogs: a file stays within its baseline, a new one '
      'has none', () {
    final baseline = readBaseline(_baselinePath);
    final census = _census();
    tightenBaselineIfAsked(_baselinePath, baseline, census);
    final problems = ratchetProblems(
      baseline: baseline,
      census: census,
      baselinePath: _baselinePath,
      noun: 'raw dialogs',
      advice: _advice,
      fix:
          'Open dialogs with showWarmDialog from $_primitive, with '
          'WarmDialogText for the body and warmDialogCancel / '
          'warmDialogConfirm for the buttons. If its shape cannot hold '
          'yours, add that shape to $_primitive (this guard allows it there) '
          'so the next dialog like it reuses it.',
    );
    if (problems.isNotEmpty) fail(problems.join('\n\n'));
  });

  test('the pattern matches the calls the primitive itself makes', () {
    // A pattern that matches nothing would pass the test above forever.
    final own = DartSource.read(_primitive).hits(_rawDialog);
    expect(own.where((h) => h.text.contains('showDialog<')), isNotEmpty);
    expect(own.where((h) => h.text.contains('AlertDialog(')), isNotEmpty);
  });

  test('every call form counts; comments, strings and wrappers do not', () {
    final source = DartSource('forms.dart', _forms);
    final found = [
      for (final hit in source.hits(_rawDialog))
        RegExp(r'\w+').matchAsPrefix(source.code, hit.offset)![0],
    ];
    expect(found, [
      'showDialog',
      'AlertDialog',
      'showDialog',
      'AlertDialog',
      'showModalBottomSheet',
      'SimpleDialog',
      'showGeneralDialog',
      'showAdaptiveDialog',
      'showCupertinoDialog',
      'showCupertinoModalPopup',
      'showBottomSheet',
      'DialogRoute',
      'RawDialogRoute',
      'ModalBottomSheetRoute',
      'CupertinoAlertDialog',
      'showDialog',
      'showAboutDialog',
      'showAdaptiveAboutDialog',
      'showRawDialog',
      'showCupertinoSheet',
      'CupertinoModalPopupRoute',
      'CupertinoModalPopupRoute',
      'CupertinoSheetRoute',
    ]);
  });
}

const _forms = r'''
Future<void> open(BuildContext context) async {
  await showDialog(context: context, builder: (_) => const AlertDialog());
  await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog.adaptive(title: Text('x')),
  );
  await showModalBottomSheet<
    void
  >(context: context, builder: (_) => const SimpleDialog());
  await showGeneralDialog(context: context, pageBuilder: build);
  await showAdaptiveDialog<void>(context: context, builder: build);
  await showCupertinoDialog(context: context, builder: build);
  await showCupertinoModalPopup<void>(context: context, builder: build);
  Scaffold.of(context).showBottomSheet((_) => const SizedBox());
  await Navigator.of(context).push(DialogRoute<void>(context: context, builder: build));
  await Navigator.of(context).push(RawDialogRoute(pageBuilder: build));
  await Navigator.of(context).push(ModalBottomSheetRoute(builder: build, isScrollControlled: true));
  const CupertinoAlertDialog();
  final link = 'https://example.com/x'; await showDialog(context: context, builder: build);
  showAboutDialog(context: context, applicationName: 'Front Porch AI');
  showAdaptiveAboutDialog(context: context);
  await showRawDialog<void>(context: context, builder: build);
  await showCupertinoSheet<void>(context: context, pageBuilder: build);
  await Navigator.of(context).push(CupertinoModalPopupRoute<void>(builder: build));
  await Navigator.of(context).push(CupertinoModalPopupRoute(builder: build));
  await Navigator.of(context).push(CupertinoSheetRoute<void>(builder: build));
  // Not counted: showDialog( in a comment, /* AlertDialog( */ in a block.
  await showWarmDialog<bool>(context, title: 'showDialog(', content: body);
  await _showDialog(context);
  await showDialogLater(link);
  final label = 'AlertDialog(${showDialogLabel(context)})';
  const Dialog(child: SizedBox());
}
''';
