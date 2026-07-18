// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Tests for ImageCommandService (the /image slash-command leaf). The leaf is
// pure orchestration over injected closures, so the whole surface is
// unit-coverable: the parse grammar (scene/last/me/char/raw/custom), the
// not-configured / busy / raw-usage guards, the craft→generate→save→attach
// happy path, and failure statuses at each stage. (The `bg`/background subcommand
// was retired along with the chat-background generation mode.)

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/chat/image_command_service.dart';

void main() {
  group('ImageCommandService.parse', () {
    test('bare / scene / here → scene', () {
      expect(ImageCommandService.parse('').kind, ImageCommandKind.scene);
      expect(ImageCommandService.parse('scene').kind, ImageCommandKind.scene);
      expect(ImageCommandService.parse('here').kind, ImageCommandKind.scene);
    });

    test('last → scene flagged as last-message-only', () {
      final r = ImageCommandService.parse('last');
      expect(r.kind, ImageCommandKind.scene);
      expect(r.text, 'last');
    });

    test('me/self → me', () {
      expect(ImageCommandService.parse('me').kind, ImageCommandKind.me);
      expect(ImageCommandService.parse('self').kind, ImageCommandKind.me);
    });

    test('char with and without a name → character', () {
      final named = ImageCommandService.parse('char Mira');
      expect(named.kind, ImageCommandKind.character);
      expect(named.text, 'Mira');
      final bare = ImageCommandService.parse('portrait');
      expect(bare.kind, ImageCommandKind.character);
      expect(bare.text, '');
    });

    test('retired bg/background keyword falls through to free-text custom', () {
      // The chat-background generation mode was removed; `bg` is no longer
      // special and is treated as an ordinary custom description.
      expect(ImageCommandService.parse('bg').kind, ImageCommandKind.custom);
      expect(
        ImageCommandService.parse('background').kind,
        ImageCommandKind.custom,
      );
    });

    test('raw keeps the rest verbatim', () {
      final r = ImageCommandService.parse('raw neon city, 8k, masterpiece');
      expect(r.kind, ImageCommandKind.raw);
      expect(r.text, 'neon city, 8k, masterpiece');
    });

    test('free text → custom with the full text', () {
      final r = ImageCommandService.parse('a dragon over the castle');
      expect(r.kind, ImageCommandKind.custom);
      expect(r.text, 'a dragon over the castle');
    });

    test('keywords are case-insensitive', () {
      expect(ImageCommandService.parse('ME').kind, ImageCommandKind.me);
      expect(ImageCommandService.parse('RAW stuff').kind, ImageCommandKind.raw);
    });
  });

  group('ImageCommandService.handle', () {
    late List<String> statuses;
    late List<String> crafted;
    late List<String> generated;
    late List<(String, String)> attached;
    late List<Object?> attachTokens;
    Object? sessionToken;
    late bool attachEnabled;
    late bool configured;
    late bool busy;
    String? craftResult;
    Uint8List? generateResult;
    String? saveResult;

    ImageCommandService build() {
      return ImageCommandService(
        isConfigured: () => configured,
        isBusy: () => busy,
        onStatus: (m, {sticky = false}) => statuses.add(m),
        craftPrompt: (req) async {
          crafted.add('${req.kind.name}:${req.text}');
          return craftResult;
        },
        generate: (prompt, req) async {
          generated.add(prompt);
          return generateResult;
        },
        saveImage: (bytes) async => saveResult,
        snapshotSession: () => sessionToken,
        attachToChat: (path, prompt, req, token) async {
          attachTokens.add(token);
          if (!attachEnabled) return false;
          attached.add((path, prompt));
          return true;
        },
      );
    }

    setUp(() {
      statuses = [];
      crafted = [];
      generated = [];
      attached = [];
      attachTokens = [];
      sessionToken = 'session-A';
      attachEnabled = true;
      configured = true;
      busy = false;
      craftResult = 'a cozy porch at dusk';
      generateResult = Uint8List.fromList([1, 2, 3]);
      saveResult = '/tmp/img.png';
    });

    test('happy path crafts, generates, saves, attaches', () async {
      await build().handle('scene');
      expect(crafted.single, 'scene:');
      expect(generated.single, 'a cozy porch at dusk');
      expect(attached.single, ('/tmp/img.png', 'a cozy porch at dusk'));
      expect(statuses.last, contains('added to the chat'));
    });

    test('raw skips crafting and sends the prompt verbatim', () async {
      await build().handle('raw neon city');
      expect(crafted, isEmpty);
      expect(generated.single, 'neon city');
      expect(attached, hasLength(1));
    });

    test('raw without a prompt reports usage', () async {
      await build().handle('raw');
      expect(statuses.single, startsWith('⚠'));
      expect(generated, isEmpty);
    });

    test('not configured → error status, nothing runs', () async {
      configured = false;
      await build().handle('');
      expect(statuses.single, startsWith('⚠'));
      expect(crafted, isEmpty);
      expect(generated, isEmpty);
    });

    test('busy → error status, nothing runs', () async {
      busy = true;
      await build().handle('');
      expect(statuses.single, startsWith('⚠'));
      expect(generated, isEmpty);
    });

    test('craft failure (empty prompt) surfaces an error and stops', () async {
      craftResult = '';
      await build().handle('scene');
      expect(statuses.last, startsWith('⚠'));
      expect(generated, isEmpty);
    });

    test('craft returning null stops silently (review cancelled — the '
        'callback owns the messaging)', () async {
      craftResult = null;
      await build().handle('scene');
      expect(statuses.where((s) => s.startsWith('⚠')), isEmpty);
      expect(generated, isEmpty);
      expect(attached, isEmpty);
    });

    test('generation failure surfaces an error and stops', () async {
      generateResult = null;
      await build().handle('scene');
      expect(statuses.last, startsWith('⚠'));
      expect(attached, isEmpty);
    });

    test('save failure surfaces an error and stops', () async {
      saveResult = null;
      await build().handle('scene');
      expect(statuses.last, startsWith('⚠'));
      expect(attached, isEmpty);
    });

    test('a second call while one is in flight is rejected', () async {
      // Make generate hang briefly so the second call overlaps the first.
      final slow = ImageCommandService(
        isConfigured: () => true,
        isBusy: () => false,
        onStatus: (m, {sticky = false}) => statuses.add(m),
        craftPrompt: (req) async => 'p',
        generate: (prompt, req) => Future<Uint8List?>.delayed(
          const Duration(milliseconds: 50),
          () => Uint8List.fromList([9]),
        ),
        saveImage: (bytes) async => '/tmp/x.png',
        attachToChat: (path, prompt, req, token) async {
          attached.add((path, prompt));
          return true;
        },
      );
      final first = slow.handle('scene');
      await slow.handle('scene'); // overlaps → rejected with busy status
      expect(statuses.where((s) => s.startsWith('⚠')), hasLength(1));
      await first;
      expect(attached, hasLength(1));
    });

    test('attach carries the session token snapshotted at run start', () async {
      sessionToken = 'session-A';
      await build().handle('scene');
      expect(attachTokens.single, 'session-A');
      expect(attached, hasLength(1));
    });

    test('a dropped attach does NOT post the success status', () async {
      attachEnabled = false; // simulate "user switched chats" → attach skipped
      await build().handle('scene');
      expect(attached, isEmpty);
      // The false success line must not appear over the drop's own status.
      expect(statuses.where((s) => s.contains('added to the chat')), isEmpty);
    });
  });
}
