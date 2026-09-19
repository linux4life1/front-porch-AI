// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// E2E: the ByafImportDialog's gallery-image handling, through the REAL
// Home page "Import Backyard AI (.byaf)" flow — the native file dialog is
// stubbed (PickerPrefs.testPickFilesOverride), everything after the pick is
// ordinary Flutter driven by real taps: ByafService.parseByaf really
// extracts the archive's images to a (sandboxed) temp directory, the dialog
// really renders the gallery-import checkbox, and
// _HomePageDialogsImport._importByaf really deletes the temp extracts and
// calls CharacterRepository.addLook — nothing about that behavior is
// reproduced or stubbed here.
//
// Three sequential sub-journeys share one boot (see model_downloader_test.dart
// for the precedent of several steps per file):
//   1. Cancel — even with the gallery checkbox left checked, cancelling must
//      not create a character or a look, and BOTH extracted temp images
//      (portrait + the one extra look) must be deleted.
//   2. Confirm with the checkbox checked — the character imports, the extra
//      image lands as a real gallery look (AvatarImage.isLook), and its temp
//      extract is deleted.
//   3. Confirm with the checkbox unchecked — the character imports, NO look
//      is added, and the temp extract is still deleted.
//
// The fixture images are a real minimal decodable PNG (not the single-byte
// stand-ins byaf_gallery_import_test.dart uses) — the confirmed path
// round-trips the portrait through V2CardService's image decode/re-encode.
//
// Run it with:
//   flutter test integration_test/porch_byaf_import_dialog_test.dart -d linux
//
// Filename sorts after model_downloader_test.dart so adding this suite does
// not move that file onto a different E2E shard (index % 5). Windows shard 5
// timed out waiting for the Model Manager Search button after the first name
// (`byaf_import_dialog_test.dart`) shifted it; this file already passed on
// Windows under that first name. Isolation contract: identical to
// app_smoke_test.dart — see its header.

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'package:front_porch_ai/main.dart' as app;
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/dialogs/dialogs.dart';
import 'package:front_porch_ai/ui/layout/main_layout.dart';
import 'package:front_porch_ai/utils/utils.dart';

import 'support/e2e_sandbox.dart';
import 'support/fake_backend.dart';

const _kReplyPieces = ['The fake backend replies ', 'about backyard imports.'];

/// A real, minimally-valid 8×8 PNG — must survive V2CardService's
/// img.decodeImage, unlike byaf_gallery_import_test.dart's `[i]` stand-ins.
const _kTinyPngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAgAAAAICAIAAABLbSncAAAAEUlEQVR42mP4/'
    'vU9VsQwtCQAafG2wXWW5mYAAAAASUVORK5CYII=';

const _kGalleryToggleText = 'Import gallery images (1 extra look)';

final _byafExtractRe = RegExp(r'^byaf_import_(\d+)_');

/// Writes a minimal .byaf archive (portrait + one extra "look") for
/// [characterName] into [dir], returning the archive's path.
String _writeByaf(Directory dir, String fileName, String characterName) {
  final pngBytes = base64Decode(_kTinyPngBase64);
  final archive = Archive()
    ..addFile(
      ArchiveFile.string(
        'manifest.json',
        jsonEncode({
          'characters': ['characters/char1/character.json'],
          'scenarios': ['scenarios/scenario1.json'],
        }),
      ),
    )
    ..addFile(
      ArchiveFile.string(
        'characters/char1/character.json',
        jsonEncode({
          'displayName': characterName,
          'persona': '{character} keeps the porch light on.',
          'images': [
            {'path': 'portrait.png'},
            {'path': 'look1.png'},
          ],
        }),
      ),
    )
    ..addFile(
      ArchiveFile.string(
        'scenarios/scenario1.json',
        jsonEncode({
          'schemaVersion': 1,
          'narrative': '{character} waits on the porch.',
          'firstMessages': [
            {'text': 'Hello {user}!'},
          ],
        }),
      ),
    )
    ..addFile(
      ArchiveFile('characters/char1/portrait.png', pngBytes.length, pngBytes),
    )
    ..addFile(
      ArchiveFile('characters/char1/look1.png', pngBytes.length, pngBytes),
    );
  final path = p.join(dir.path, fileName);
  File(path).writeAsBytesSync(ZipEncoder().encode(archive));
  return path;
}

/// Every `byaf_import_*` extract currently sitting in [tmpDir].
Set<String> _extractedTempPaths(Directory tmpDir) => tmpDir.existsSync()
    ? tmpDir
          .listSync()
          .whereType<File>()
          .map((f) => f.path)
          .where((path) => _byafExtractRe.hasMatch(p.basename(path)))
          .toSet()
    : <String>{};

/// The extracts that showed up in [tmpDir] since [before] was captured,
/// keyed by their index in the archive (0 = portrait, 1 = the extra look).
Map<int, String> _newExtracts(Directory tmpDir, Set<String> before) {
  final result = <int, String>{};
  for (final path in _extractedTempPaths(tmpDir).difference(before)) {
    final index = int.parse(
      _byafExtractRe.firstMatch(p.basename(path))!.group(1)!,
    );
    result[index] = path;
  }
  return result;
}

/// Opens the real BYAF import flow — empty library shows a direct
/// "Import BYAF" button; a non-empty one uses the grid toolbar import menu.
Future<void> _openByafDialog(WidgetTester tester) async {
  final emptyStateButton = find.widgetWithText(ElevatedButton, 'Import BYAF');
  if (emptyStateButton.evaluate().isNotEmpty) {
    await tester.tap(emptyStateButton);
  } else {
    await tester.tap(find.byTooltip('Import or discover characters'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Import Backyard AI (.byaf)'));
  }
  await pumpUntilFound(tester, find.byType(ByafImportDialog));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'ByafImportDialog gallery-look handling: cancel discards everything, '
    'confirm respects the checkbox, temp extracts are always cleaned up — '
    'sandboxed',
    (tester) async {
      try {
        final probe = await Socket.connect(
          InternetAddress.loopbackIPv4,
          5001,
          timeout: const Duration(milliseconds: 500),
        );
        probe.destroy();
        fail(
          'Something is listening on 127.0.0.1:5001 (a real KoboldCpp?). '
          'Close it before running the E2E suite.',
        );
      } on SocketException {
        // Nothing there — safe to proceed.
      }

      final sandbox = Directory.systemTemp.createTempSync('fpai_byafdlg_');
      PathProviderPlatform.instance = SandboxPathProvider(sandbox.path);
      final backend = await FakeBackendServer.start(replyPieces: _kReplyPieces);
      SharedPreferences.setMockInitialValues({
        'update_auto_check': false,
        'import_llmerta_porch_memories': false,
        'realism_default': false,
        'backend_type': 'openRouter',
        'remote_api_url': '${backend.baseUrl}/v1',
        'remote_model_name': 'smoke-model',
      });

      final tmpDir = Directory(p.join(sandbox.path, 'tmp'));
      final fixtureDir = Directory(p.join(sandbox.path, 'fixtures'))
        ..createSync(recursive: true);

      var pickCalls = 0;
      String? askedCategory;
      List<String>? askedExtensions;
      String currentFixturePath = '';
      PickerPrefs.testPickFilesOverride =
          ({required String category, List<String>? allowedExtensions}) async {
            pickCalls++;
            askedCategory = category;
            askedExtensions = allowedExtensions;
            final file = File(currentFixturePath);
            return FilePickerResult([
              MemoryPlatformFile(
                name: p.basename(currentFixturePath),
                bytes: file.readAsBytesSync(),
              ),
            ]);
          };
      addTearDown(() => PickerPrefs.testPickFilesOverride = null);

      app.main(const []);
      await pumpUntilFound(tester, find.byType(MainLayout));
      try {
        await windowManager.setAlwaysOnTop(true);
        await windowManager.setSize(const Size(1200, 800));
        await windowManager.setAlignment(Alignment.bottomRight);
        await windowManager.blur();
      } catch (e) {
        debugPrint('[e2e] window_manager placement skipped: $e');
      }
      await tester.pump(const Duration(seconds: 2));

      final ctx = tester.element(find.byType(MainLayout));
      final repo = Provider.of<CharacterRepository>(ctx, listen: false);

      currentFixturePath = _writeByaf(fixtureDir, 'cancel.byaf', 'Cancel Case');
      var before = _extractedTempPaths(tmpDir);
      await _openByafDialog(tester);
      expect(pickCalls, 1);
      expect(askedCategory, PickerPrefs.catImport);
      expect(askedExtensions, ['byaf']);
      expect(find.text('Cancel Case'), findsOneWidget);

      var extracts = _newExtracts(tmpDir, before);
      expect(extracts.keys.toSet(), {
        0,
        1,
      }, reason: 'both the portrait and the one extra look must be extracted');

      final galleryCheckbox = find.widgetWithText(
        CheckboxListTile,
        _kGalleryToggleText,
      );
      expect(
        tester.widget<CheckboxListTile>(galleryCheckbox).value,
        isTrue,
        reason: 'the gallery-import checkbox defaults to checked',
      );

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(ByafImportDialog), findsNothing);

      expect(
        repo.characters.any((c) => c.name == 'Cancel Case'),
        isFalse,
        reason: 'cancelling must not import a character',
      );
      for (final path in extracts.values) {
        expect(
          File(path).existsSync(),
          isFalse,
          reason: 'cancel must delete every extracted temp image ($path)',
        );
      }

      currentFixturePath = _writeByaf(
        fixtureDir,
        'checked.byaf',
        'Checked Case',
      );
      before = _extractedTempPaths(tmpDir);
      await _openByafDialog(tester);
      expect(find.text('Checked Case'), findsOneWidget);
      extracts = _newExtracts(tmpDir, before);
      expect(extracts.keys.toSet(), {0, 1});
      expect(
        tester
            .widget<CheckboxListTile>(
              find.widgetWithText(CheckboxListTile, _kGalleryToggleText),
            )
            .value,
        isTrue,
      );
      final checkedLookTemp = extracts[1]!;

      await tester.tap(find.widgetWithText(ElevatedButton, 'Import Character'));
      await pumpUntilTrue(
        tester,
        () =>
            repo.characters.any((c) => c.name == 'Checked Case') &&
            !File(checkedLookTemp).existsSync(),
        describe: () =>
            'the imported character to land and its look extract to be '
            'cleaned up (repo has: '
            '${repo.characters.map((c) => c.name).toList()})',
        timeout: const Duration(seconds: 30),
      );

      final checkedCard = repo.characters.firstWhere(
        (c) => c.name == 'Checked Case',
      );
      final checkedLooks = (await repo.getAvatarImages(
        checkedCard.dbId!,
      )).where((a) => a.isLook).toList();
      expect(
        checkedLooks,
        hasLength(1),
        reason: 'the checked gallery-import toggle must add the extra look',
      );
      expect(
        File(checkedLookTemp).existsSync(),
        isFalse,
        reason: 'the look temp extract must be deleted after import',
      );

      currentFixturePath = _writeByaf(
        fixtureDir,
        'unchecked.byaf',
        'Unchecked Case',
      );
      before = _extractedTempPaths(tmpDir);
      await _openByafDialog(tester);
      expect(find.text('Unchecked Case'), findsOneWidget);
      extracts = _newExtracts(tmpDir, before);
      expect(extracts.keys.toSet(), {0, 1});
      final uncheckedLookTemp = extracts[1]!;

      await tester.tap(
        find.widgetWithText(CheckboxListTile, _kGalleryToggleText),
      );
      await tester.pump();
      expect(
        tester
            .widget<CheckboxListTile>(
              find.widgetWithText(CheckboxListTile, _kGalleryToggleText),
            )
            .value,
        isFalse,
        reason: 'the toggle must actually flip off before confirming',
      );

      await tester.tap(find.widgetWithText(ElevatedButton, 'Import Character'));
      await pumpUntilTrue(
        tester,
        () =>
            repo.characters.any((c) => c.name == 'Unchecked Case') &&
            !File(uncheckedLookTemp).existsSync(),
        describe: () =>
            'the imported character to land and its look extract to be '
            'cleaned up (repo has: '
            '${repo.characters.map((c) => c.name).toList()})',
        timeout: const Duration(seconds: 30),
      );

      final uncheckedCard = repo.characters.firstWhere(
        (c) => c.name == 'Unchecked Case',
      );
      final uncheckedLooks = (await repo.getAvatarImages(
        uncheckedCard.dbId!,
      )).where((a) => a.isLook).toList();
      expect(
        uncheckedLooks,
        isEmpty,
        reason:
            'the unchecked gallery-import toggle must not add a gallery look',
      );
      expect(
        File(uncheckedLookTemp).existsSync(),
        isFalse,
        reason:
            'the look temp extract must still be deleted even when the '
            'checkbox is unchecked',
      );

      await tester.pump(const Duration(seconds: 1));
      await backend.close();
      try {
        sandbox.deleteSync(recursive: true);
      } on FileSystemException {
        // A straggler may still be writing; not a failure.
      }
    },
  );
}
