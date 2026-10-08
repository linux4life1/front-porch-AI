// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/image/comfy_gguf_city96_gate.dart';
import 'package:front_porch_ai/services/image/comfy_gguf_city96_write.dart'
    show kCity96OthersCanWrite;
import 'package:front_porch_ai/ui/dialogs/city96_loader_dialog.dart';

void main() {
  const question = City96Question(
    loaderPath: '/tmp/ComfyUI/custom_nodes/ComfyUI-GGUF/loader.py',
    comfyUrl: 'http://127.0.0.1:8188',
  );

  Future<bool?> ask(WidgetTester tester, Future<void> Function() answer) async {
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async =>
                result = await showCity96LoaderDialog(context, question),
            child: const Text('go'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('Update the ComfyUI-GGUF loader?'), findsOneWidget);
    expect(find.textContaining(question.loaderPath), findsOneWidget);
    expect(find.textContaining('loader.py.bak'), findsOneWidget);
    expect(find.textContaining('restarted'), findsOneWidget);
    await answer();
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('Update loader answers yes', (tester) async {
    expect(
      await ask(tester, () => tester.tap(find.text('Update loader'))),
      isTrue,
    );
  });

  testWidgets('Not now answers no', (tester) async {
    expect(await ask(tester, () => tester.tap(find.text('Not now'))), isFalse);
  });

  testWidgets('closing the dialog is a no', (tester) async {
    expect(
      await ask(tester, () async {
        Navigator.of(tester.element(find.byType(AlertDialog))).pop();
      }),
      isFalse,
    );
  });

  Future<void> open(WidgetTester tester, {required bool others}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showCity96LoaderDialog(
              context,
              City96Question(
                loaderPath: question.loaderPath,
                comfyUrl: question.comfyUrl,
                othersCanWrite: others,
              ),
            ),
            child: const Text('go'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
  }

  testWidgets('warns when other users can change the folder', (tester) async {
    await open(tester, others: true);

    expect(find.textContaining(kCity96OthersCanWrite), findsOneWidget);
    expect(find.text('Update loader'), findsOneWidget);
  });

  testWidgets('says nothing about it when they cannot', (tester) async {
    await open(tester, others: false);

    expect(find.textContaining(kCity96OthersCanWrite), findsNothing);
  });
}
