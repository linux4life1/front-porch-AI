// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The Windows side of the loader update, on any machine: the rules for reading
// a security descriptor, the table of listeners, what is asked of a path, and
// the writer's steps (which handles it opens and how, and what it does when a
// call fails), against an in-memory Windows file system behind the same calls.
// The calls themselves are checked on a Windows runner in
// city96_windows_real_test.dart.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/image/city96_exclusive_write_windows.dart';
import 'package:front_porch_ai/services/image/city96_write_common.dart';
import 'package:front_porch_ai/services/image/comfy_process_probe_windows.dart';
import 'package:front_porch_ai/services/image/windows_acl.dart';
import 'package:front_porch_ai/services/image/windows_api.dart';
import 'package:front_porch_ai/services/image/windows_api_security.dart';

import 'city96_test_loader.dart';
import 'fake_win32.dart';

const _me = 'S-1-5-21-1-2-3-1001';
const _everyone = 'S-1-1-0';
const _users = 'S-1-5-32-545';
const _authenticated = 'S-1-5-11';
const _interactive = 'S-1-5-4';

WindowsAce _allow(String sid, int mask, {int flags = 0}) =>
    WindowsAce(type: kAceAllowed, flags: flags, mask: mask, sid: sid);

void main() {
  group('who counts as another user', () {
    test('this user, the system and its administrators do not', () {
      for (final sid in [
        _me,
        kSidSystem,
        kSidAdministrators,
        kSidTrustedInstaller,
        kSidOwnerRights,
      ]) {
        expect(windowsSidIsTrusted(sid, _me), isTrue, reason: sid);
      }
    });

    test('everyone else does', () {
      for (final sid in [_everyone, _users, _authenticated, _interactive]) {
        expect(windowsSidIsTrusted(sid, _me), isFalse, reason: sid);
      }
    });

    test('generic rights become file rights before they are compared', () {
      expect(mapGenericFileMask(0x40000000), 0x120116);
      expect(mapGenericFileMask(0x80000000), 0x120089);
      expect(mapGenericFileMask(0x10000000), 0x1F01FF);
      expect(mapGenericFileMask(0x120116), 0x120116);
    });
  });

  group('whether others can write', () {
    bool folder(List<WindowsAce> aces) =>
        windowsOthersCanWrite(aces, me: _me, folder: true);
    bool file(List<WindowsAce> aces) =>
        windowsOthersCanWrite(aces, me: _me, folder: false);

    test('Everyone, Users, Authenticated Users and INTERACTIVE with write', () {
      for (final sid in [_everyone, _users, _authenticated, _interactive]) {
        expect(folder([_allow(sid, 0x120116)]), isTrue, reason: sid);
        expect(file([_allow(sid, 0x120116)]), isTrue, reason: sid);
      }
    });

    test('generic write and full control count', () {
      expect(folder([_allow(_users, 0x40000000)]), isTrue);
      expect(folder([_allow(_users, 0x10000000)]), isTrue);
    });

    test(
      'rights to delete a folder\'s files or change its permissions count',
      () {
        expect(folder([_allow(_users, 0x40)]), isTrue); // delete child
        expect(folder([_allow(_users, 0x40000)]), isTrue); // write DAC
        expect(folder([_allow(_users, 0x80000)]), isTrue); // write owner
      },
    );

    test('read and execute alone do not', () {
      expect(folder([_allow(_everyone, 0x1200A9)]), isFalse);
      expect(file([_allow(_everyone, 0x1200A9)]), isFalse);
    });

    test('this user and the system writing is nobody else', () {
      expect(
        folder([
          _allow(_me, 0x1F01FF),
          _allow(kSidSystem, 0x1F01FF),
          _allow(kSidAdministrators, 0x1F01FF),
          _allow(kSidTrustedInstaller, 0x1F01FF),
        ]),
        isFalse,
      );
    });

    test('a deny entry is ignored: it can be removed', () {
      final deny = WindowsAce(
        type: kAceDenied,
        flags: 0,
        mask: 0x120116,
        sid: _everyone,
      );
      expect(folder([deny]), isFalse);
      expect(folder([deny, _allow(_users, 0x120116)]), isTrue);
    });

    test(
      'an inherit-only entry counts for a folder only when files inherit it',
      () {
        expect(
          folder([_allow(_users, 0x120116, flags: kAceInheritOnly)]),
          isFalse,
        );
        expect(
          folder([
            _allow(
              _users,
              0x120116,
              flags: kAceInheritOnly | kAceObjectInherit,
            ),
          ]),
          isTrue,
        );
        // A file's own list has no use for an entry that only passes on.
        expect(
          file([
            _allow(
              _users,
              0x120116,
              flags: kAceInheritOnly | kAceObjectInherit,
            ),
          ]),
          isFalse,
        );
      },
    );

    test(
      'an owner that is not this user is told apart from an administrator',
      () {
        expect(windowsOwnerVerdict(_me, _me), WindowsOwnerVerdict.mine);
        expect(
          windowsOwnerVerdict(kSidAdministrators, _me),
          WindowsOwnerVerdict.administrator,
        );
        expect(
          windowsOwnerVerdict(kSidSystem, _me),
          WindowsOwnerVerdict.administrator,
        );
        expect(
          windowsOwnerVerdict('S-1-5-21-9-9-9-500', _me),
          WindowsOwnerVerdict.someoneElse,
        );
      },
    );
  });

  group('the listener tables', () {
    Uint8List v4(List<(int port, int pid)> rows) {
      final data = ByteData(4 + rows.length * 24);
      data.setUint32(0, rows.length, Endian.little);
      for (var i = 0; i < rows.length; i++) {
        final at = 4 + i * 24;
        final (port, pid) = rows[i];
        data.setUint32(at, 2, Endian.little); // listening
        data.setUint32(
          at + 8,
          ((port & 0xFF) << 8) | (port >> 8),
          Endian.little,
        );
        data.setUint32(at + 20, pid, Endian.little);
      }
      return data.buffer.asUint8List();
    }

    Uint8List v6(List<(int port, int pid)> rows) {
      final data = ByteData(4 + rows.length * 56);
      data.setUint32(0, rows.length, Endian.little);
      for (var i = 0; i < rows.length; i++) {
        final at = 4 + i * 56;
        final (port, pid) = rows[i];
        data.setUint32(
          at + 20,
          ((port & 0xFF) << 8) | (port >> 8),
          Endian.little,
        );
        data.setUint32(at + 48, 2, Endian.little);
        data.setUint32(at + 52, pid, Endian.little);
      }
      return data.buffer.asUint8List();
    }

    test('a row is read by its port, in network byte order', () {
      expect(
        parseTcpListenerTable(v4([(8188, 11), (8080, 12)]), 8188, v6: false),
        {11},
      );
      expect(parseTcpListenerTable(v6([(8188, 21), (9, 22)]), 8188, v6: true), {
        21,
      });
      expect(parseTcpListenerTable(v4([(8188, 11)]), 9999, v6: false), isEmpty);
    });

    test('an empty or cut-off table is no listener', () {
      expect(parseTcpListenerTable(Uint8List(0), 8188, v6: false), isEmpty);
      final cut = v4([(8188, 11)]).sublist(0, 20);
      expect(parseTcpListenerTable(cut, 8188, v6: false), isEmpty);
    });

    test('only this user\'s processes are candidates, IPv4 and IPv6', () async {
      final api = FakeWin32Security(
        v4Table: v4([(8188, 11), (8188, 12)]),
        v6Table: v6([(8188, 13), (8188, 14)]),
        pidSids: {11: _me, 12: 'S-1-5-21-9-9-9-1002', 13: _me},
      );
      // 12 belongs to someone else; 14 cannot be opened (access denied).
      expect(await windowsListeningPids(8188, api: api), {11, 13});
    });

    test('a listener on IPv6 only is found', () async {
      final api = FakeWin32Security(
        v4Table: v4([]),
        v6Table: v6([(8188, 13)]),
        pidSids: {13: _me},
      );
      expect(await windowsListeningPids(8188, api: api), {13});
    });

    test('a process that listens on another port is not', () async {
      final api = FakeWin32Security(
        v4Table: v4([(8080, 11)]),
        v6Table: v6([]),
        pidSids: {11: _me},
      );
      expect(await windowsListeningPids(8188, api: api), isEmpty);
    });

    test(
      'a table that cannot be read, or an unknown user, is no answer',
      () async {
        expect(
          await windowsListeningPids(
            8188,
            api: FakeWin32Security(v4Table: null, v6Table: v6([])),
          ),
          isNull,
        );
        expect(
          await windowsListeningPids(
            8188,
            api: FakeWin32Security(v4Table: v4([]), v6Table: null),
          ),
          isNull,
        );
        expect(
          await windowsListeningPids(
            8188,
            api: FakeWin32Security(me: null, v4Table: v4([]), v6Table: v6([])),
          ),
          isNull,
        );
      },
    );

    test('whether a process is this user\'s, and when it started', () async {
      final t = DateTime.utc(2026, 1, 2, 3, 4, 5);
      final api = FakeWin32Security(
        pidSids: {11: _me, 12: 'S-1-5-21-9-9-9-1002'},
        starts: {11: t},
      );
      expect(await windowsProcessIsMine(11, api: api), isTrue);
      expect(await windowsProcessIsMine(12, api: api), isFalse);
      expect(await windowsProcessIsMine(13, api: api), isFalse);
      expect(await windowsProcessStart(11, api: api), t);
      expect(await windowsProcessStart(12, api: api), isNull);
    });
  });

  group('what a path says about who owns and who may change it', () {
    const folderPath = r'C:\ComfyUI\custom_nodes\ComfyUI-GGUF';
    late FakeWin32Api files;

    setUp(() {
      files = FakeWin32Api()..addFolder(folderPath);
    });

    Future<dynamic> facts(FakeWin32Security security, {String? path}) {
      security.pathOf = files.pathForHandle;
      return windowsPathFacts(
        path ?? folderPath,
        folder: true,
        files: files,
        security: security,
      );
    }

    test('this user, nobody else able to write', () async {
      final f = await facts(FakeWin32Security());
      expect(f.owner, _me);
      expect(f.ownerIsAdmin, isFalse);
      expect(f.isLink, isFalse);
      expect(f.othersCanWrite, isFalse);
      expect(f.problem, isNull);
      expect(files.openHandles, isEmpty, reason: 'every handle is closed');
    });

    test('Users can write: said, not refused', () async {
      final f = await facts(
        FakeWin32Security(
          acls: {
            folderPath.toLowerCase(): [_allow(_users, 0x120116)],
          },
        ),
      );
      expect(f.othersCanWrite, isTrue);
      expect(f.problem, isNull);
    });

    test('an administrator or SYSTEM owner is one, not a stranger', () async {
      for (final sid in [kSidAdministrators, kSidSystem]) {
        final f = await facts(
          FakeWin32Security(owners: {folderPath.toLowerCase(): sid}),
        );
        expect(f.owner, sid);
        expect(f.ownerIsAdmin, isTrue, reason: sid);
      }
    });

    test('another user\'s own SID is not an administrator', () async {
      final f = await facts(
        FakeWin32Security(
          owners: {folderPath.toLowerCase(): 'S-1-5-21-9-9-9-1002'},
        ),
      );
      expect(f.owner, isNot(_me));
      expect(f.ownerIsAdmin, isFalse);
    });

    test('no access list at all is refused', () async {
      final f = await facts(
        FakeWin32Security(nullDacl: {folderPath.toLowerCase()}),
      );
      expect(f.problem, contains('no access list'));
    });

    test('a junction or symbolic link is a link', () async {
      files.reparse.add(folderPath.toLowerCase());
      expect((await facts(FakeWin32Security())).isLink, isTrue);
    });

    test(
      'a substituted drive or a short name is a link: the path is not what it resolves to',
      () async {
        files.finalPathOf[folderPath.toLowerCase()] =
            r'\\?\D:\Elsewhere\ComfyUI-GGUF';
        expect((await facts(FakeWin32Security())).isLink, isTrue);

        files.finalPathOf[folderPath.toLowerCase()] =
            r'\\?\C:\COMFYU~1\custom_nodes\ComfyUI-GGUF';
        expect((await facts(FakeWin32Security())).isLink, isTrue);
      },
    );

    test('case and a trailing separator are not a difference', () async {
      files.finalPathOf[folderPath.toLowerCase()] =
          r'\\?\c:\comfyui\CUSTOM_NODES\comfyui-gguf\';
      expect((await facts(FakeWin32Security())).isLink, isFalse);
    });

    test(
      'every call that fails is no answer, and no handle is left open',
      () async {
        for (final failing in ['createFile', 'handleAttributes', 'finalPath']) {
          final fs = FakeWin32Api()..addFolder(folderPath);
          if (failing == 'createFile') {
            fs.failing['createFile:ComfyUI-GGUF'] = 5;
          } else {
            fs.failing[failing] = 5;
          }
          final security = FakeWin32Security()..pathOf = fs.pathForHandle;
          expect(
            await windowsPathFacts(
              folderPath,
              folder: true,
              files: fs,
              security: security,
            ),
            isNull,
            reason: failing,
          );
          expect(fs.openHandles, isEmpty, reason: failing);
        }
        final security = FakeWin32Security(securityFails: true)
          ..pathOf = files.pathForHandle;
        expect(
          await windowsPathFacts(
            folderPath,
            folder: true,
            files: files,
            security: security,
          ),
          isNull,
        );
        expect(files.openHandles, isEmpty);
        expect(
          await windowsPathFacts(
            folderPath,
            folder: true,
            files: files,
            security: FakeWin32Security(me: null),
          ),
          isNull,
        );
      },
    );

    test('the verbatim spelling of a path', () {
      expect(windowsVerbatim(r'C:\a\b'), r'\\?\C:\a\b');
      expect(windowsVerbatim(r'\\srv\share\a'), r'\\?\UNC\srv\share\a');
      expect(windowsVerbatim(r'\\?\C:\a'), r'\\?\C:\a');
    });
  });

  group('the writer', () {
    const folder = r'C:\ComfyUI\custom_nodes\ComfyUI-GGUF';
    const loaderPath = '$folder\\loader.py';
    const bakPath = '$loaderPath.bak';
    late FakeWin32Api fs;

    setUp(() {
      fs = FakeWin32Api()
        ..addFolder(folder)
        ..addFile(loaderPath, kStockCity96Loader);
    });

    Future<void> write({void Function(String)? afterCreate}) =>
        writeCity96LoaderWindows(
          File(loaderPath),
          'patched',
          api: fs,
          afterCreate: afterCreate,
        );

    List<String> leftovers() => [
      for (final path in fs.paths)
        if (path.contains('fpai-tmp')) path,
    ];

    test(
      'replaces loader.py, keeps the original as loader.py.bak, leaves nothing',
      () async {
        await write();

        expect(fs.text(loaderPath), 'patched');
        expect(fs.text(bakPath), kStockCity96Loader);
        expect(leftovers(), isEmpty);
        expect(fs.openHandles, isEmpty);
      },
    );

    test(
      'the folder is held without delete sharing; the new files are shared with no one',
      () async {
        await write();

        final held = fs.opened.firstWhere((o) => o.path == folder);
        expect(held.share & kShareDelete, 0, reason: 'it cannot be renamed');
        final created = fs.opened.where((o) => o.disposition == kCreateNew);
        expect(created, hasLength(2), reason: 'the backup and the temp file');
        for (final o in created) {
          expect(o.share, 0, reason: o.path);
          expect(o.access & kDelete, isNot(0), reason: 'renamed by handle');
        }
      },
    );

    test('the temp name is not guessable', () async {
      await write();
      final temps = fs.opened
          .where((o) => o.path.contains('fpai-tmp'))
          .map((o) => o.path)
          .toList();
      expect(temps.single, matches(RegExp(r'fpai-tmp-[0-9a-f]{32}$')));
    });

    test('an existing backup stays as it is', () async {
      fs.addFile(bakPath, 'the first original');
      await write();

      expect(fs.text(bakPath), 'the first original');
      expect(fs.text(loaderPath), 'patched');
    });

    test(
      'a failed write does not remove a backup that was already there',
      () async {
        fs.addFile(bakPath, 'the first original');
        fs.failing['writeAll'] = 112;
        await expectLater(write(), throwsA(isA<City96WriteRefused>()));
        expect(fs.text(bakPath), 'the first original');
      },
    );

    for (final which in ['fpai-tmp', '.bak']) {
      test(
        'the $which file swapped for a link after it is created is not kept',
        () async {
          // Between creating a new file and writing it, it becomes a link.
          void swap(String path) {
            if (path.contains(which)) fs.reparse.add(path.toLowerCase());
          }

          await expectLater(
            write(afterCreate: swap),
            throwsA(isA<City96WriteRefused>()),
          );

          expect(fs.text(loaderPath), kStockCity96Loader);
          expect(leftovers(), isEmpty);
          expect(fs.openHandles, isEmpty);
        },
      );
    }

    test('a link as the loader is refused before anything is made', () async {
      fs.reparse.add(loaderPath.toLowerCase());
      await expectLater(write(), throwsA(isA<City96WriteRefused>()));
      expect(fs.exists(bakPath), isFalse);
      expect(fs.text(loaderPath), kStockCity96Loader);
    });

    test(
      'a folder that is a link, or not where it is spelled, is refused',
      () async {
        fs.reparse.add(folder.toLowerCase());
        await expectLater(write(), throwsA(isA<City96WriteRefused>()));
        fs.reparse.clear();
        fs.finalPathOf[folder.toLowerCase()] = r'\\?\D:\Other\ComfyUI-GGUF';
        await expectLater(write(), throwsA(isA<City96WriteRefused>()));
        expect(fs.exists(bakPath), isFalse);
        expect(leftovers(), isEmpty);
      },
    );

    test(
      'a fault before the rename leaves the original and cleans up',
      () async {
        fs.failing['renameEx'] = 87;
        fs.failing['renamePlain'] = 87;
        fs.failing['move'] = 5;

        await expectLater(write(), throwsA(isA<City96WriteRefused>()));

        expect(fs.text(loaderPath), kStockCity96Loader);
        expect(
          fs.exists(bakPath),
          isFalse,
          reason: 'the backup this call made',
        );
        expect(leftovers(), isEmpty);
        expect(fs.openHandles, isEmpty);
      },
    );

    test(
      'the rename tries by handle with POSIX semantics, then plain, then a move',
      () async {
        fs.failing['renameEx'] = 87;
        await write();
        expect(fs.renames, ['ex', 'plain']);

        fs = FakeWin32Api()
          ..addFolder(folder)
          ..addFile(loaderPath, kStockCity96Loader)
          ..failing['renameEx'] = 87
          ..failing['renamePlain'] = 50;
        await write();
        expect(fs.renames, ['ex', 'plain', 'move']);
        expect(fs.text(loaderPath), 'patched');
        expect(fs.openHandles, isEmpty);
      },
    );

    group(
      'each call that fails refuses, leaves no temp file and no open handle',
      () {
        for (final call in [
          'createFile:ComfyUI-GGUF',
          'createFile:loader.py',
          'createFile:loader.py.bak',
          'createFile:temp',
          'readAll',
          'writeAll',
          'flush',
          'handleAttributes',
          'finalPath',
          'renameEx',
        ]) {
          test(call, () async {
            fs.failing[call] = 5;
            if (call == 'renameEx') {
              fs.failing['renamePlain'] = 5;
              fs.failing['move'] = 5;
            }
            await expectLater(write(), throwsA(isA<City96WriteRefused>()));

            expect(fs.text(loaderPath), kStockCity96Loader);
            expect(leftovers(), isEmpty);
            expect(fs.openHandles, isEmpty);
            expect(fs.text(bakPath), isNull, reason: 'made by this call');
          });
        }
      },
    );

    test(
      'the loader is read through a checked handle, and only read',
      () async {
        await write();
        final read = fs.opened.firstWhere(
          (o) => o.path == loaderPath && o.disposition == kOpenExisting,
        );
        expect(read.access, kGenericRead);
        expect(read.access & kGenericWrite, 0);
      },
    );

    test('non-ASCII text is written as UTF-8', () async {
      await writeCity96LoaderWindows(File(loaderPath), 'π', api: fs);
      expect(fs.text(loaderPath), isNotNull);
      expect(utf8.decode(fs.text(loaderPath)!.codeUnits), 'π');
    });
  });
}
