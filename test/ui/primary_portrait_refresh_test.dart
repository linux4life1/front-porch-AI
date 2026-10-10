// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/ui/pages/home/cards/cards.dart';
import 'package:front_porch_ai/ui/chat_components/chat_components.dart';
import 'package:front_porch_ai/ui/dialogs/avatar_gallery/avatar_gallery_controller.dart';
import 'package:front_porch_ai/ui/dialogs/avatar_gallery/avatar_tile.dart';
import 'image_studio/expression_workspace_test.dart' as fixture;

void main() {
  testWidgets(
    'replacing the primary portrait refreshes cached grid, gallery and chat pixels without restarting',
    (tester) async {
      final rig = await fixture.workspaceRig(tester);
      final controller = AvatarGalleryController(
        libraryCard: rig.first,
        repository: rig.repository,
        storage: rig.storage,
        mode: WardrobeMode.library,
      );
      Future<void> show() => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                CharacterPortrait(
                  file: File(rig.first.imagePath!),
                  size: 100,
                  imageKey: 'default:${rig.repository.coverEpoch}',
                ),
                SizedBox(
                  width: 180,
                  height: 240,
                  child: CharacterGridCard(
                    character: rig.first,
                    activeFolderId: null,
                    messageCountCache: {},
                    isSelecting: false,
                    isOrganizing: false,
                    selectedCharacterIds: {},
                    onTapCharacter: (_) async {},
                    onToggleSelect: (_) {},
                    onContextMenuAction: (_, _) {},
                    onResolveCharImage: (card) => File(card.imagePath!),
                    imageCacheEpoch: rig.repository.coverEpoch,
                  ),
                ),
                SizedBox(
                  width: 180,
                  height: 240,
                  child: AvatarTile(
                    imageFile: File(rig.first.imagePath!),
                    starred: false,
                    onStar: () {},
                    imageVersion: controller.mediaGen,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      Future<List<int>> reds() async {
        for (var i = 0; i < 100; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump();
          final images = tester
              .widgetList<RawImage>(find.byType(RawImage))
              .map((w) => w.image)
              .toList();
          if (images.length == 3 && images.every((image) => image != null)) {
            final pixels = await tester.runAsync(
              () async => Future.wait(
                images.map(
                  (image) =>
                      image!.toByteData(format: ui.ImageByteFormat.rawRgba),
                ),
              ),
            );
            return pixels!.map((data) => data!.getUint8(0)).toList();
          }
        }
        throw StateError('Portrait images never loaded');
      }

      await show();
      expect(await reds(), [100, 100, 100]);
      await tester.runAsync(
        () => controller.replacePortrait(fixture.workspacePicture(210)),
      );
      expect(controller.lastError, isNull);
      await show();
      await tester.pump(const Duration(milliseconds: 400));
      expect(await reds(), [210, 210, 210]);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      await tester.pump(const Duration(milliseconds: 1));
    },
  );
}
