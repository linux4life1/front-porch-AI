// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:typed_data';

import 'package:front_porch_ai/services/image/windows_acl.dart';
import 'package:front_porch_ai/services/image/windows_api.dart';
import 'package:front_porch_ai/services/image/windows_api_security.dart';

/// A small in-memory Windows file system behind the same calls the real
/// [Win32Api] makes, so the loader writer's logic runs on any machine: which
/// handles it opens and how, what it writes through them, and what it does
/// when one call fails. Paths compare ignoring case, as Windows does.
class FakeWin32Api extends Win32Api {
  FakeWin32Api();

  final Map<String, _Node> _nodes = {};
  final Map<int, _Open> _open = {};
  int _next = 100;

  /// Every createFile call, in order.
  final List<({String path, int access, int share, int disposition})> opened =
      [];

  /// Calls that fail, by method name, with the error they return.
  final Map<String, int> failing = {};

  /// Paths (lowercase) whose final path differs (a substituted drive, a short
  /// name), and the final path they report.
  final Map<String, String> finalPathOf = {};

  /// 8.3 short names (lowercase) and the long name each stands for. Windows
  /// spells every one out in a final path and in GetLongPathName.
  final Map<String, String> shortNames = {};

  String _long(String path) =>
      path.split(r'\').map((s) => shortNames[s.toLowerCase()] ?? s).join(r'\');

  /// Renames (`renameEx`, `renamePlain`, `move`) that report success and do
  /// nothing, as the by-handle rename did with a wrong buffer layout.
  final Set<String> silent = {};

  /// A failed createFile reports error 0, as GetLastError does when something
  /// else has already reset it.
  bool loseErrors = false;

  /// Paths that are reparse points (junctions, symbolic links).
  final Set<String> reparse = {};

  /// A hook run right after a new file is created, before it is written.
  void Function(String path)? onCreated;

  /// The renames tried, in order: 'ex', 'plain' or 'move'.
  final List<String> renames = [];

  /// The handles still open.
  Set<int> get openHandles => _open.keys.toSet();

  static String _key(String path) => path.toLowerCase();

  void addFolder(String path) => _nodes[_key(path)] = _Node.folder();

  void addFile(String path, String text) =>
      _nodes[_key(path)] = _Node.file(Uint8List.fromList(text.codeUnits));

  bool exists(String path) => _nodes.containsKey(_key(path));

  String? text(String path) {
    final node = _nodes[_key(path)];
    return node == null ? null : String.fromCharCodes(node.bytes);
  }

  List<String> get paths => _nodes.keys.toList();

  /// The path a handle was opened for.
  String pathForHandle(int handle) => _open[handle]!.path;

  int _fail(String method) => failing[method] ?? 0;

  @override
  (int, int) createFile(
    String path,
    int access,
    int share,
    int disposition,
    int flags,
  ) {
    opened.add((
      path: path,
      access: access,
      share: share,
      disposition: disposition,
    ));
    final name = path.split(r'\').last;
    final call = 'createFile:${name.contains('fpai-tmp') ? 'temp' : name}';
    if (_fail(call) != 0) return (kInvalidHandle, _fail(call));
    final key = _key(path);
    if (disposition == kCreateNew) {
      if (_nodes.containsKey(key)) {
        return (kInvalidHandle, loseErrors ? 0 : kErrorFileExists);
      }
      _nodes[key] = _Node.file(Uint8List(0));
      onCreated?.call(path);
    } else if (!_nodes.containsKey(key)) {
      return (kInvalidHandle, 2);
    }
    final h = _next++;
    _open[h] = _Open(key, path);
    return (h, 0);
  }

  @override
  void closeHandle(int handle) => _open.remove(handle);

  _Node _node(int handle) => _nodes[_open[handle]!.key]!;

  @override
  int writeAll(int handle, Uint8List bytes) {
    if (_fail('writeAll') != 0) return _fail('writeAll');
    final node = _node(handle);
    node.bytes = Uint8List.fromList([...node.bytes, ...bytes]);
    return 0;
  }

  @override
  (Uint8List?, int) readAll(int handle) {
    if (_fail('readAll') != 0) return (null, _fail('readAll'));
    return (_node(handle).bytes, 0);
  }

  @override
  int flush(int handle) => _fail('flush');

  @override
  int? handleAttributes(int handle) {
    if (_fail('handleAttributes') != 0) return null;
    final open = _open[handle]!;
    final node = _node(handle);
    return (node.folder ? 0x10 : 0x20) |
        (reparse.contains(open.key) ? kAttributeReparsePoint : 0);
  }

  @override
  int? pathAttributes(String path) =>
      _nodes.containsKey(_key(path)) ? 0x20 : null;

  @override
  String? finalPath(int handle) {
    if (_fail('finalPath') != 0) return null;
    final open = _open[handle]!;
    return finalPathOf[open.key] ?? '\\\\?\\${_long(open.path)}';
  }

  @override
  String? longPath(String path) => _fail('longPath') != 0 ? null : _long(path);

  @override
  int renameByHandle(int handle, String target, {required bool ex}) {
    renames.add(ex ? 'ex' : 'plain');
    final err = _fail(ex ? 'renameEx' : 'renamePlain');
    if (err != 0) return err;
    if (silent.contains(ex ? 'renameEx' : 'renamePlain')) return 0;
    final open = _open[handle]!;
    final node = _nodes.remove(open.key)!;
    _nodes[_key(target)] = node;
    _open[handle] = _Open(_key(target), target);
    return 0;
  }

  @override
  int moveReplacing(String from, String to) {
    renames.add('move');
    if (_fail('move') != 0) return _fail('move');
    if (silent.contains('move')) return 0;
    final node = _nodes.remove(_key(from));
    if (node == null) return 2;
    _nodes[_key(to)] = node;
    return 0;
  }

  @override
  bool deletePath(String path) {
    _nodes.remove(_key(path));
    return true;
  }
}

class _Node {
  _Node.file(this.bytes) : folder = false;
  _Node.folder() : bytes = Uint8List(0), folder = true;

  Uint8List bytes;
  final bool folder;
}

class _Open {
  _Open(this.key, this.path);

  final String key;
  final String path;
}

/// Security facts and processes behind the same calls the real
/// [Win32SecurityApi] makes.
class FakeWin32Security extends Win32SecurityApi {
  FakeWin32Security({
    this.me = 'S-1-5-21-1-2-3-1001',
    this.owners = const {},
    this.acls = const {},
    this.nullDacl = const {},
    this.pidSids = const {},
    this.starts = const {},
    this.v4Table,
    this.v6Table,
    this.securityFails = false,
  });

  final String? me;

  /// Owner SID by lowercase path; anything else is owned by [me].
  final Map<String, String> owners;
  final Map<String, List<WindowsAce>> acls;
  final Set<String> nullDacl;
  final Map<int, String> pidSids;
  final Map<int, DateTime> starts;
  final Uint8List? v4Table;
  final Uint8List? v6Table;
  final bool securityFails;

  /// Handles opened by FakeWin32Api map back to paths through this.
  String Function(int handle)? pathOf;

  @override
  (WindowsSecurity?, int) security(int handle) {
    if (securityFails) return (null, 5);
    final path = pathOf!(handle).toLowerCase();
    final owner = owners[path] ?? me!;
    if (nullDacl.contains(path)) {
      return (WindowsSecurity(owner: owner, aces: null), 0);
    }
    return (WindowsSecurity(owner: owner, aces: acls[path] ?? const []), 0);
  }

  @override
  String? currentUserSid() => me;

  @override
  String? pidUserSid(int pid) => pidSids[pid];

  @override
  DateTime? processStart(int pid) => starts[pid];

  @override
  Uint8List? tcpListenerTable(int family) => family == 2 ? v4Table : v6Table;
}
