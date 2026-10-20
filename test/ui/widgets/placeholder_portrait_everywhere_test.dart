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

import 'package:provider/provider.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/chat_components/chat_components.dart';
import 'package:front_porch_ai/ui/dialogs/dialogs.dart';
import 'package:front_porch_ai/ui/pages/create_group_chat_page.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';
import 'package:front_porch_ai/utils/utils.dart';

import '../../golden/support/creator_test_support.dart';
import '../../golden/support/fakes.dart';
import '../../golden/support/fakes_storage.dart';

/// Every character sits at the library root.
class _RootOnlyFolders extends FakeFolderService {
  @override
  CharacterFolder? getFolderForCharacter(String imagePath) => null;
}

/// The file [image] reads, through a sized decode ([ResizeImage]).
String? _pathOf(ImageProvider? image) => switch (image) {
  FileImage(:final file) => file.path,
  ResizeImage(:final imageProvider) => _pathOf(imageProvider),
  _ => null,
};

/// [Image] widgets drawing [file].
int _imagesShowing(WidgetTester tester, File file) => tester
    .widgetList<Image>(find.byType(Image))
    .where((i) => _pathOf(i.image) == file.path)
    .length;

/// Circles drawing [file] as their picture.
int _circlesShowing(WidgetTester tester, File file) => tester
    .widgetList<CircleAvatar>(find.byType(CircleAvatar))
    .where((c) => _pathOf(c.backgroundImage) == file.path)
    .length;

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
  setupPathProviderMock();

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

  testWidgets('the Create Group Chat picker and roster show the person icon', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 950));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final repo = FakeCharacterRepository([
      CharacterCard(name: 'Juniper', imagePath: placeholder.path),
      CharacterCard(name: 'Marlow', imagePath: real.path),
    ]);
    final chat = FakeChatService();
    final storage = FakeStorageService();
    final worlds = FakeWorldRepository();
    final folders = _RootOnlyFolders();
    final groups = FakeGroupChatRepository();
    final llm = FakeLLMProvider();
    final tts = FakeTtsService();
    for (final s in [repo, chat, storage, worlds, folders, groups, llm, tts]) {
      addTearDown(s.dispose);
    }
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<CharacterRepository>.value(value: repo),
          ChangeNotifierProvider<ChatService>.value(value: chat),
          ChangeNotifierProvider<StorageService>.value(value: storage),
          ChangeNotifierProvider<WorldRepository>.value(value: worlds),
          ChangeNotifierProvider<FolderService>.value(value: folders),
          ChangeNotifierProvider<GroupChatRepository>.value(value: groups),
          ChangeNotifierProvider<LLMProvider>.value(value: llm),
          ChangeNotifierProvider<TtsService>.value(value: tts),
        ],
        child: const MaterialApp(home: CreateGroupChatPage()),
      ),
    );
    await tester.pumpAndSettle();

    // Cold: no circle in the picker draws a picture yet.
    expect(_circlesShowing(tester, placeholder), 0);
    expect(_circlesShowing(tester, real), 0);

    await _letProbesFinish(tester);
    // Marlow's portrait; Juniper keeps the person icon, never her flat box.
    expect(_circlesShowing(tester, real), 1);
    expect(_circlesShowing(tester, placeholder), 0);
    expect(find.byIcon(Icons.person), findsOneWidget);

    // Both join the roster, which draws them the same way.
    for (final name in ['Juniper', 'Marlow']) {
      await tester.tap(find.text(name).first);
      await tester.pumpAndSettle();
    }
    expect(find.text('Current Roster (2)'), findsOneWidget);
    expect(_circlesShowing(tester, real), 1);
    expect(_circlesShowing(tester, placeholder), 0);
    expect(find.byIcon(Icons.person), findsOneWidget);
  });

  testWidgets('the chat sidebar portrait, cast strip and member card', (
    tester,
  ) async {
    final chat = FakeChatService(realismEnabled: false);
    addTearDown(chat.dispose);
    Widget member(String name, File file) => GroupMemberCard(
      character: CharacterCard(name: name),
      chatService: chat,
      avatarColor: AppColors.formMasterAccent,
      isNextSpeaker: false,
      isExpanded: false,
      onTap: () {},
      avatarFile: file,
    );
    Widget chip(String name, File file) => CastRosterChip(
      name: name,
      color: AppColors.formMasterAccent,
      isFocused: false,
      isLite: false,
      imageFile: file,
      onFocus: () {},
    );
    await tester.binding.setSurfaceSize(const Size(900, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _host(
        SingleChildScrollView(
          child: Column(
            children: [
              for (final (name, file) in [
                ('Juniper', placeholder),
                ('Marlow', real),
              ]) ...[
                CharacterPortrait(file: file, size: 120),
                chip(name, file),
                SizedBox(width: 320, child: member(name, file)),
              ],
            ],
          ),
        ),
      ),
    );
    // Cold: no picture is drawn before the probe answers.
    expect(_imagesShowing(tester, placeholder), 0);
    expect(_imagesShowing(tester, real), 0);

    await _letProbesFinish(tester);
    expect(_imagesShowing(tester, real), 3);
    expect(_imagesShowing(tester, placeholder), 0);
    // Juniper: the sidebar's person tile, her initial on the chip and card.
    expect(find.byIcon(Icons.person), findsOneWidget);
    expect(find.text('J'), findsNWidgets(2));
  });

  testWidgets(
    'a chat bubble shows the person icon beside the reply',
    timeout: const Timeout(Duration(minutes: 1)),
    (tester) async {
      final storage = (await tester.runAsync(makeGoldenStorage))!;
      addTearDown(storage.dispose);
      final chat = FakeChatService();
      addTearDown(chat.dispose);
      final tts = FakeTtsService();
      addTearDown(tts.dispose);
      Widget bubble(String name, File file) => MessageBubble(
        message: ChatMessage(text: 'Evening.', sender: name, isUser: false),
        index: 0,
        chatService: chat,
        characterImage: file,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MultiProvider(
              providers: [
                ChangeNotifierProvider<StorageService>.value(value: storage),
                ChangeNotifierProvider<TtsService>.value(value: tts),
                ChangeNotifierProvider<ChatService>.value(value: chat),
                ChangeNotifierProvider<UserPersonaService>.value(
                  value: FakeUserPersonaService(),
                ),
              ],
              child: ListView(
                children: [
                  bubble('Juniper', placeholder),
                  bubble('Marlow', real),
                ],
              ),
            ),
          ),
        ),
      );
      expect(_imagesShowing(tester, placeholder), 0);
      expect(_imagesShowing(tester, real), 0);

      await _letProbesFinish(tester);
      expect(_imagesShowing(tester, real), 1);
      expect(_imagesShowing(tester, placeholder), 0);
      expect(find.byIcon(Icons.person), findsOneWidget);
      // A 32 px avatar decodes small, not the full portrait.
      final avatar = tester
          .widgetList<Image>(find.byType(Image))
          .singleWhere((i) => _pathOf(i.image) == real.path);
      expect((avatar.image as ResizeImage).width, kPortraitAvatarDecodeWidth);
    },
  );

  testWidgets('the /join scene guest picker shows the person icon', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SceneGuestPickerDialog(
            characters: [
              CharacterCard(name: 'Juniper', imagePath: placeholder.path),
              CharacterCard(name: 'Marlow', imagePath: real.path),
            ],
            resolveImage: (c) => File(c.imagePath!),
          ),
        ),
      ),
    );
    // Cold: neither row draws its picture before the probe answers.
    expect(_circlesShowing(tester, placeholder), 0);
    expect(_circlesShowing(tester, real), 0);

    await _letProbesFinish(tester);
    expect(_circlesShowing(tester, real), 1);
    expect(_circlesShowing(tester, placeholder), 0);
    expect(find.byIcon(Icons.person), findsOneWidget);
  });

  testWidgets('the group goals dialog member row shows the initial', (
    tester,
  ) async {
    // The member row has a known layout overflow (see the dialog's golden).
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.exceptionAsString().contains('overflowed')) return;
      previous?.call(details);
    };
    addTearDown(() => FlutterError.onError = previous);
    final chat = FakeChatService();
    addTearDown(chat.dispose);
    final members = [
      CharacterCard(name: 'Juniper', imagePath: placeholder.path),
      CharacterCard(name: 'Marlow', imagePath: real.path),
    ];
    await tester.binding.setSurfaceSize(const Size(640, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GroupObjectivesDialog(
            chatService: chat,
            groupCharacters: members,
            initialCharacter: members.first,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(_circlesShowing(tester, placeholder), 0);
    expect(_circlesShowing(tester, real), 0);

    await _letProbesFinish(tester);
    expect(_circlesShowing(tester, real), 1);
    expect(_circlesShowing(tester, placeholder), 0);
    expect(find.text('J'), findsOneWidget);
  });
}
