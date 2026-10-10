// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// A character made without a portrait still carries a flat 400×600 colour
// picture in its card file. Home's own card shows the person icon for it
// (no_portrait_placeholder_test.dart); these pin the other places that drew
// the flat box: folder and group mosaics, roster circles and chat avatars.
// Every case starts cold (nothing probed yet), as a user's first paint does:
// the picture is drawn only once the probe has said it is real.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

/// A real photo at the placeholder's exact size: one of the app's own
/// background pictures, cropped.
File _realPortrait400x600(String path) {
  final photo = img.decodeImage(
    File('assets/backgrounds/beach.png').readAsBytesSync(),
  )!;
  final square = img.copyResizeCropSquare(photo, size: 600);
  final cropped = img.copyCrop(square, x: 100, y: 0, width: 400, height: 600);
  return File(path)..writeAsBytesSync(img.encodePng(cropped));
}

/// Lets the probes the widgets started finish on real time: file reads and
/// the decode isolate do not run under the widget test's fake clock, and each
/// step's callback lands in the next pump.
Future<void> _letProbesFinish(WidgetTester tester) async {
  for (var i = 0; i < 40; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 15)),
    );
    await tester.pump();
  }
}

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(body: Center(child: child)),
);

/// Montage cells drawing a picture (a [DecorationImage]).
Iterable<BoxDecoration> _pictureCells(WidgetTester tester) => tester
    .widgetList<Container>(find.byType(Container))
    .map((c) => c.decoration)
    .whereType<BoxDecoration>()
    .where((d) => d.image != null);

void main() {
  late Directory root;
  late File placeholder;
  late File real;

  setUp(() async {
    PlaceholderPortraitProbe.clearCache();
    root = Directory.systemTemp.createTempSync('fpai_placeholder_spots_');
    placeholder = File(p.join(root.path, 'Juniper_1.png'));
    // The exact file the creators write for "no portrait yet".
    await V2CardService().saveCardAsPng(
      CharacterCard(name: 'Juniper'),
      placeholder.path,
      null,
    );
    real = _realPortrait400x600(p.join(root.path, 'Marlow_1.png'));
  });

  tearDown(() => root.deleteSync(recursive: true));

  testWidgets('folder and group mosaics show the person icon, not the box', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(GroupAvatarMontage(images: [placeholder, real], side: 160)),
    );
    // Cold: neither cell draws its picture before the probe answers.
    expect(_pictureCells(tester), isEmpty);
    expect(find.byIcon(Icons.person), findsNWidgets(2));

    await _letProbesFinish(tester);
    // The real portrait is drawn; the placeholder keeps the person icon.
    final pictures = _pictureCells(tester).toList();
    expect(pictures, hasLength(1));
    final provider = pictures.single.image!.image as ResizeImage;
    expect((provider.imageProvider as FileImage).file.path, real.path);
    expect(find.byIcon(Icons.person), findsOneWidget);
  });
}
