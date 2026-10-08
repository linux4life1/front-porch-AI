// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// The Win32 calls the loader update needs, each behind a method that reads
// GetLastError right after its call, so a test can replace one and make it
// fail. The libraries are opened when a call is made, never at import, so
// this file loads (and its parsers run) on any OS.

import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'windows_acl.dart';

const int kInvalidHandle = -1;

// Access, sharing, disposition and flag values used by the callers.
const int kReadControl = 0x20000;
const int kFileReadAttributes = 0x80;
const int kGenericRead = 0x80000000;
const int kGenericWrite = 0x40000000;
const int kDelete = 0x10000;
const int kShareRead = 1;
const int kShareWrite = 2;
const int kShareDelete = 4;
const int kCreateNew = 1;
const int kOpenExisting = 3;
const int kFlagOpenReparsePoint = 0x00200000;
const int kFlagBackupSemantics = 0x02000000;
const int kFlagWriteThrough = 0x80000000;
const int kAttributeReparsePoint = 0x400;
const int kErrorFileExists = 80;
const int kErrorInsufficientBuffer = 122;

/// One security descriptor, read: who owns it and its allow/deny entries.
/// [aces] is null when the object has no DACL at all (everyone may do
/// anything), which is not the same as an empty one.
class WindowsSecurity {
  const WindowsSecurity({required this.owner, required this.aces});

  final String owner;
  final List<WindowsAce>? aces;
}

class Win32Api {
  const Win32Api();

  static final DynamicLibrary _k32 = DynamicLibrary.open('kernel32.dll');

  static final _getLastError = _k32
      .lookupFunction<Uint32 Function(), int Function()>(
        'GetLastError',
        isLeaf: true,
      );
  static final _createFile = _k32
      .lookupFunction<
        IntPtr Function(
          Pointer<Utf16>,
          Uint32,
          Uint32,
          Pointer<Void>,
          Uint32,
          Uint32,
          IntPtr,
        ),
        int Function(Pointer<Utf16>, int, int, Pointer<Void>, int, int, int)
      >('CreateFileW', isLeaf: true);
  static final _closeHandle = _k32
      .lookupFunction<Int32 Function(IntPtr), int Function(int)>(
        'CloseHandle',
        isLeaf: true,
      );
  static final _writeFile = _k32
      .lookupFunction<
        Int32 Function(
          IntPtr,
          Pointer<Uint8>,
          Uint32,
          Pointer<Uint32>,
          Pointer<Void>,
        ),
        int Function(int, Pointer<Uint8>, int, Pointer<Uint32>, Pointer<Void>)
      >('WriteFile', isLeaf: true);
  static final _readFile = _k32
      .lookupFunction<
        Int32 Function(
          IntPtr,
          Pointer<Uint8>,
          Uint32,
          Pointer<Uint32>,
          Pointer<Void>,
        ),
        int Function(int, Pointer<Uint8>, int, Pointer<Uint32>, Pointer<Void>)
      >('ReadFile', isLeaf: true);
  static final _flush = _k32
      .lookupFunction<Int32 Function(IntPtr), int Function(int)>(
        'FlushFileBuffers',
        isLeaf: true,
      );
  static final _getFileSizeEx = _k32
      .lookupFunction<
        Int32 Function(IntPtr, Pointer<Int64>),
        int Function(int, Pointer<Int64>)
      >('GetFileSizeEx', isLeaf: true);
  static final _getFileInfo = _k32
      .lookupFunction<
        Int32 Function(IntPtr, Pointer<Uint8>),
        int Function(int, Pointer<Uint8>)
      >('GetFileInformationByHandle', isLeaf: true);
  static final _getAttributes = _k32
      .lookupFunction<
        Uint32 Function(Pointer<Utf16>),
        int Function(Pointer<Utf16>)
      >('GetFileAttributesW', isLeaf: true);
  static final _finalPath = _k32
      .lookupFunction<
        Uint32 Function(IntPtr, Pointer<Utf16>, Uint32, Uint32),
        int Function(int, Pointer<Utf16>, int, int)
      >('GetFinalPathNameByHandleW', isLeaf: true);
  static final _getLongPath = _k32
      .lookupFunction<
        Uint32 Function(Pointer<Utf16>, Pointer<Utf16>, Uint32),
        int Function(Pointer<Utf16>, Pointer<Utf16>, int)
      >('GetLongPathNameW', isLeaf: true);
  static final _setInfo = _k32
      .lookupFunction<
        Int32 Function(IntPtr, Int32, Pointer<Uint8>, Uint32),
        int Function(int, int, Pointer<Uint8>, int)
      >('SetFileInformationByHandle', isLeaf: true);
  static final _moveFileEx = _k32
      .lookupFunction<
        Int32 Function(Pointer<Utf16>, Pointer<Utf16>, Uint32),
        int Function(Pointer<Utf16>, Pointer<Utf16>, int)
      >('MoveFileExW', isLeaf: true);

  /// Opens [path]. The handle is [kInvalidHandle] on failure; [err] is
  /// GetLastError right after the call.
  (int handle, int err) createFile(
    String path,
    int access,
    int share,
    int disposition,
    int flags,
  ) {
    final name = path.toNativeUtf16();
    try {
      final h = _createFile(
        name,
        access,
        share,
        nullptr,
        disposition,
        flags,
        0,
      );
      return (h, h == kInvalidHandle ? _getLastError() : 0);
    } finally {
      calloc.free(name);
    }
  }

  void closeHandle(int handle) {
    if (handle != kInvalidHandle && handle != 0) _closeHandle(handle);
  }

  /// Writes every byte, looping over short writes. Returns the error (0 = ok).
  int writeAll(int handle, Uint8List bytes) {
    final buf = calloc<Uint8>(bytes.isEmpty ? 1 : bytes.length);
    final done = calloc<Uint32>();
    try {
      buf.asTypedList(bytes.length).setAll(0, bytes);
      var at = 0;
      while (at < bytes.length) {
        final ok = _writeFile(
          handle,
          buf + at,
          bytes.length - at,
          done,
          nullptr,
        );
        if (ok == 0) return _getLastError();
        if (done.value == 0) return 1;
        at += done.value;
      }
      return 0;
    } finally {
      calloc.free(buf);
      calloc.free(done);
    }
  }

  /// Reads the whole file behind [handle]. Null (and [err]) on failure.
  (Uint8List? data, int err) readAll(int handle) {
    final size = calloc<Int64>();
    try {
      if (_getFileSizeEx(handle, size) == 0) return (null, _getLastError());
      final total = size.value;
      if (total < 0 || total > 16 * 1024 * 1024) return (null, 1);
      final buf = calloc<Uint8>(total == 0 ? 1 : total);
      final got = calloc<Uint32>();
      try {
        var at = 0;
        while (at < total) {
          final ok = _readFile(handle, buf + at, total - at, got, nullptr);
          if (ok == 0) return (null, _getLastError());
          if (got.value == 0) break;
          at += got.value;
        }
        return (Uint8List.fromList(buf.asTypedList(at)), 0);
      } finally {
        calloc.free(buf);
        calloc.free(got);
      }
    } finally {
      calloc.free(size);
    }
  }

  int flush(int handle) => _flush(handle) == 0 ? _getLastError() : 0;

  /// The file attributes behind [handle], or null.
  int? handleAttributes(int handle) {
    final info = calloc<Uint8>(52);
    try {
      if (_getFileInfo(handle, info) == 0) return null;
      return ByteData.sublistView(
        info.asTypedList(52),
      ).getUint32(0, Endian.little);
    } finally {
      calloc.free(info);
    }
  }

  /// The attributes of [path], or null.
  int? pathAttributes(String path) {
    final name = path.toNativeUtf16();
    try {
      final a = _getAttributes(name);
      return a == 0xFFFFFFFF ? null : a;
    } finally {
      calloc.free(name);
    }
  }

  /// The final path of [handle] (`\\?\C:\...`), or null.
  String? finalPath(int handle) {
    const cap = 32768;
    final buf = calloc<Uint16>(cap).cast<Utf16>();
    try {
      final n = _finalPath(handle, buf, cap, 0);
      if (n == 0 || n >= cap) return null;
      return buf.toDartString(length: n);
    } finally {
      calloc.free(buf);
    }
  }

  /// [path] with every 8.3 short name in it (`RUNNER~1`) spelled out, or null
  /// when it cannot be expanded (it does not exist, or the call failed).
  String? longPath(String path) {
    const cap = 32768;
    final name = path.toNativeUtf16();
    final buf = calloc<Uint16>(cap).cast<Utf16>();
    try {
      final n = _getLongPath(name, buf, cap);
      if (n == 0 || n >= cap) return null;
      return buf.toDartString(length: n);
    } finally {
      calloc.free(name);
      calloc.free(buf);
    }
  }

  /// Renames the file behind [handle] to [target] (a full path), replacing
  /// what is there. [ex] uses FileRenameInfoEx with POSIX semantics. Returns
  /// the error (0 = ok).
  int renameByHandle(int handle, String target, {required bool ex}) {
    final bytes = fileRenameInfo(target, ex: ex, pointerSize: sizeOf<IntPtr>());
    final info = calloc<Uint8>(bytes.length);
    try {
      info.asTypedList(bytes.length).setAll(0, bytes);
      final ok = _setInfo(handle, ex ? 22 : 3, info, bytes.length);
      return ok == 0 ? _getLastError() : 0;
    } finally {
      calloc.free(info);
    }
  }

  /// Removes the file at [path]; false when it cannot be.
  bool deletePath(String path) {
    try {
      final f = File(path);
      if (f.existsSync()) f.deleteSync();
      return true;
    } on FileSystemException {
      return false;
    }
  }

  /// MoveFileExW with REPLACE_EXISTING | WRITE_THROUGH. The error (0 = ok).
  int moveReplacing(String from, String to) {
    final a = from.toNativeUtf16();
    final b = to.toNativeUtf16();
    try {
      return _moveFileEx(a, b, 0x1 | 0x8) == 0 ? _getLastError() : 0;
    } finally {
      calloc.free(a);
      calloc.free(b);
    }
  }
}

/// The FILE_RENAME_INFO buffer for renaming to [target] (a full path).
///
/// Layout: the flags (or ReplaceIfExists) as a DWORD; the root directory
/// HANDLE, aligned to the pointer size (offset 8 on x64, 4 on x86); the name
/// length in bytes, right after it; then the name, a DWORD later (offset 20 on
/// x64, 12 on x86). [ex] asks for replace-if-exists and POSIX semantics.
Uint8List fileRenameInfo(
  String target, {
  required bool ex,
  required int pointerSize,
}) {
  final name = '\\\\?\\$target'.codeUnits;
  final lengthAt = pointerSize * 2;
  final nameAt = lengthAt + 4;
  final bytes = Uint8List(nameAt + name.length * 2 + 2);
  final data = ByteData.sublistView(bytes);
  data.setUint32(0, ex ? 0x3 : 0x1, Endian.little);
  data.setUint32(lengthAt, name.length * 2, Endian.little);
  for (var i = 0; i < name.length; i++) {
    data.setUint16(nameAt + i * 2, name[i], Endian.little);
  }
  return bytes;
}
