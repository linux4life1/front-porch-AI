// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:front_porch_ai/ui/chat_components/chat_components.dart';
import 'package:front_porch_ai/utils/utils.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

Uint8List _tinyPng() =>
    Uint8List.fromList(img.encodePng(img.Image(width: 8, height: 8)));

base class _SizedPlatformFile extends PlatformFile {
  _SizedPlatformFile({
    required this.name,
    required this.reportedLength,
    required this.bytes,
  });

  @override
  final String name;
  final int reportedLength;
  final Uint8List bytes;
  var streamRead = false;

  @override
  Uri get uri => Uri(scheme: 'memory', path: '/$name');

  @override
  XFile get xFile => XFile.fromData(bytes, name: name);

  @override
  Future<int> length() async => reportedLength;

  @override
  Future<Uint8List> readAsBytes() async {
    throw StateError('photo picker must use the bounded byte stream');
  }

  @override
  Stream<Uint8List> readAsByteStream() async* {
    streamRead = true;
    yield bytes;
  }
}

void main() {
  test('filename allowlist is PNG, JPEG, and WebP only', () {
    expect(looksLikeImageFileName('shot.PNG'), isTrue);
    expect(looksLikeImageFileName('shot.jpeg'), isTrue);
    expect(looksLikeImageFileName('shot.webp'), isTrue);
    expect(looksLikeImageFileName('animated.gif'), isFalse);
    expect(looksLikeImageFileName('huge.bmp'), isFalse);
    expect(looksLikeImageFileName('phone.heic'), isFalse);
    expect(looksLikeImageFileName('notes.dart'), isFalse);
  });

  test('firstDroppedImage skips non-images and keeps a png', () async {
    final png = _tinyPng();
    final got = await firstDroppedImage([
      (
        name: 'readme.md',
        length: () async => 3,
        openRead: () => Stream.value(Uint8List.fromList([1, 2, 3])),
      ),
      (
        name: 'shot.png',
        length: () async => png.length,
        openRead: () => Stream.value(png),
      ),
    ]);
    expect(got, isNotNull);
    expect(got!.length, greaterThan(8));
  });

  test('oversized drop and picker are rejected before readAsBytes', () async {
    var droppedRead = false;
    final dropped = await firstDroppedImage([
      (
        name: 'huge.png',
        length: () async => kChatImageMaxFileBytes + 1,
        openRead: () {
          droppedRead = true;
          return Stream.value(_tinyPng());
        },
      ),
    ]);
    expect(dropped, isNull);
    expect(droppedRead, isFalse);

    final picked = _SizedPlatformFile(
      name: 'huge.png',
      reportedLength: kChatImageMaxFileBytes + 1,
      bytes: _tinyPng(),
    );
    PickerPrefs.testPickFilesOverride =
        ({required category, allowedExtensions}) async =>
            FilePickerResult([picked]);
    addTearDown(() => PickerPrefs.testPickFilesOverride = null);
    expect(await pickChatImageAttachment(), isNull);
    expect(picked.streamRead, isFalse);
  });

  test(
    'bounded stream rejects a file that grows after its length check',
    () async {
      final bytes = await readBoundedImageBytes(
        Stream.value([1, 2, 3]),
        maxBytes: 2,
      );
      expect(bytes, isNull);
    },
  );

  test('header dimensions are bounded before pixel decode', () async {
    final png = _tinyPng();
    expect(await prepareChatImageBytes(png, maxDecodePixels: 63), isNull);
    expect(await prepareChatImageBytes(png), isNotNull);
    final bmp = Uint8List.fromList(
      img.encodeBmp(img.Image(width: 8, height: 8)),
    );
    expect(await prepareChatImageBytes(bmp), isNull);
  });

  test(
    'inbox refuses unprepared or oversized bytes before creating it',
    () async {
      final root = await Directory.systemTemp.createTemp('waifu_inbox_bound_');
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
      });
      await expectLater(
        waifuSaveInboxPhoto(root.path, Uint8List.fromList([1, 2, 3])),
        throwsFormatException,
      );
      await expectLater(
        waifuSaveInboxPhoto(root.path, Uint8List(kWaifuInboxPhotoMaxBytes + 1)),
        throwsFormatException,
      );
      expect(
        await Directory(p.join(root.path, kWaifuInboxDir)).exists(),
        isFalse,
      );
    },
  );

  test(
    'harness first generate carries the photo; later steps do not',
    () async {
      final root = await Directory.systemTemp.createTemp('waifu_img_');
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
      });
      final png = _tinyPng();
      final path = await waifuSaveInboxPhoto(root.path, png);
      expect(File(path).existsSync(), isTrue);
      expect(p.basename(p.dirname(path)), 'inbox');
      expect(
        p.relative(path, from: root.path).replaceAll(r'\', '/'),
        startsWith('$kWaifuInboxDir/'),
      );

      final llm = ScriptedWaifuLlm([
        const LlmToolResponse(calls: [], text: 'Hmph. I see it.'),
      ]);
      final session = WaifuSession(
        folderRoot: root.path,
        coworker: CharacterCard(name: 'Iris'),
      );
      await WaifuHarness(
        session: session,
        llm: llm,
      ).send('what is this', imagePng: png, imagePath: path);
      expect(llm.calls, hasLength(1));
      expect(llm.calls.first.images, isNotNull);
      expect(llm.calls.first.images, isNotEmpty);
      expect(session.transcript.first.imagePath, path);
      expect(
        session.transcript.first
            .toChatMessage('Iris')
            .activeMetadata?['is_user_image'],
        isTrue,
      );
    },
  );
}
