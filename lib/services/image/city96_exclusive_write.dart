// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// Creates [path] (which must not exist, and is not followed if it is a link)
/// and writes [bytes] through the descriptor that creation returned, so
/// nothing can redirect the write between the two. The file ends with exactly
/// [mode] whatever the umask. Throws [PathExistsException] when the name is
/// taken, and [UnsupportedError] where this cannot be done safely.
/// [afterCreate] is for tests.
void writeNewFileExclusive(
  String path,
  List<int> bytes, {
  required int mode,
  void Function(String path)? afterCreate,
}) {
  final flags = _flags();
  if (flags == null) {
    throw UnsupportedError('exclusive writes are not supported here');
  }
  final libc = DynamicLibrary.process();
  final open = libc
      .lookupFunction<
        Int32 Function(Pointer<Utf8>, Int32, VarArgs<(Int32,)>),
        int Function(Pointer<Utf8>, int, int)
      >('open');
  final write = libc
      .lookupFunction<
        IntPtr Function(Int32, Pointer<Uint8>, IntPtr),
        int Function(int, Pointer<Uint8>, int)
      >('write');
  final fchmod = libc
      .lookupFunction<Int32 Function(Int32, Int32), int Function(int, int)>(
        'fchmod',
      );
  final fsync = libc.lookupFunction<Int32 Function(Int32), int Function(int)>(
    'fsync',
  );
  final close = libc.lookupFunction<Int32 Function(Int32), int Function(int)>(
    'close',
  );
  final name = path.toNativeUtf8();
  int fd;
  try {
    fd = open(name, flags, 0x180); // 0600; the final mode is set below.
  } finally {
    calloc.free(name);
  }
  if (fd < 0) {
    if (FileSystemEntity.typeSync(path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw PathExistsException(path, const OSError('File exists', 17));
    }
    throw FileSystemException('could not create the file', path);
  }
  final buffer = calloc<Uint8>(bytes.isEmpty ? 1 : bytes.length);
  try {
    afterCreate?.call(path);
    buffer.asTypedList(bytes.length).setAll(0, bytes);
    var done = 0;
    while (done < bytes.length) {
      final n = write(fd, buffer + done, bytes.length - done);
      if (n <= 0) throw FileSystemException('could not write the file', path);
      done += n;
    }
    if (fchmod(fd, mode) != 0) {
      throw FileSystemException('could not set the file mode', path);
    }
    if (fsync(fd) != 0) {
      throw FileSystemException('could not flush the file', path);
    }
  } finally {
    calloc.free(buffer);
    close(fd);
  }
}

/// O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC for this platform, or
/// null when it is not known.
int? _flags() {
  const wronly = 1;
  final abi = Abi.current();
  if (abi == Abi.macosArm64 || abi == Abi.macosX64) {
    return wronly | 0x200 | 0x800 | 0x100 | 0x1000000;
  }
  if (Platform.isLinux) {
    final x86 = abi == Abi.linuxX64 || abi == Abi.linuxIA32;
    return wronly | 0x40 | 0x80 | 0x80000 | (x86 ? 0x20000 : 0x8000);
  }
  return null;
}
