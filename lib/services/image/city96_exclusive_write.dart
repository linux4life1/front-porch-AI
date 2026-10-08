// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'city96_exclusive_write_windows.dart';
import 'city96_write_common.dart';

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
  if (Platform.isWindows) {
    writeNewFileExclusiveWindows(path, bytes, afterCreate: afterCreate);
    return;
  }
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
  Pointer<Uint8>? buffer;
  try {
    buffer = calloc<Uint8>(bytes.isEmpty ? 1 : bytes.length);
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
    if (buffer != null) calloc.free(buffer);
    close(fd);
  }
}

/// Reads all of [path], which is opened without following a link, so a
/// loader that was swapped for a link since it was judged is refused and never
/// read through. Non-blocking, so a pipe put there cannot hang the read.
/// Throws [City96WriteRefused] for a link, [UnsupportedError] where this
/// cannot be done safely. [afterOpen] is for tests.
///
/// [onMode] is given the permission bits of the file that was opened, taken
/// through the open descriptor (`/dev/fd/N` is the descriptor, not the name,
/// so nothing swapped in at the name since is looked at).
Uint8List readFileNoFollow(
  String path, {
  void Function(String path)? afterOpen,
  void Function(int mode)? onMode,
}) {
  final os = _osFlags();
  if (Platform.isWindows || os == null) {
    throw UnsupportedError('no-follow reads are not supported here');
  }
  final libc = DynamicLibrary.process();
  final open = libc
      .lookupFunction<
        Int32 Function(Pointer<Utf8>, Int32, VarArgs<(Int32,)>),
        int Function(Pointer<Utf8>, int, int)
      >('open');
  final read = libc
      .lookupFunction<
        IntPtr Function(Int32, Pointer<Uint8>, IntPtr),
        int Function(int, Pointer<Uint8>, int)
      >('read');
  final close = libc.lookupFunction<Int32 Function(Int32), int Function(int)>(
    'close',
  );
  final name = path.toNativeUtf8();
  int fd;
  try {
    fd = open(name, os.nofollow | os.cloexec | os.nonblock, 0);
  } finally {
    calloc.free(name);
  }
  if (fd < 0) {
    if (FileSystemEntity.typeSync(path, followLinks: false) ==
        FileSystemEntityType.link) {
      throw const City96WriteRefused(
        'Its ComfyUI-GGUF loader was replaced by a link while it was being '
        'read, so nothing was changed.',
      );
    }
    throw FileSystemException('could not open the file', path);
  }
  const chunk = 64 * 1024;
  const cap = 16 * 1024 * 1024;
  final buffer = calloc<Uint8>(chunk);
  final out = BytesBuilder(copy: false);
  try {
    afterOpen?.call(path);
    if (onMode != null) onMode(_descriptorMode(libc, fd, path));
    while (true) {
      final n = read(fd, buffer, chunk);
      if (n < 0) throw FileSystemException('could not read the file', path);
      if (n == 0) break;
      out.add(Uint8List.fromList(buffer.asTypedList(n)));
      if (out.length > cap) {
        throw FileSystemException('the file is too large to copy', path);
      }
    }
    return out.takeBytes();
  } finally {
    calloc.free(buffer);
    close(fd);
  }
}

/// Permission bits of the open file [fd]. macOS `/dev/fd/N` reports the
/// descriptor's own access (a read-only open of a 0640 file shows 0440), so
/// macOS asks `fstat`; Linux `/dev/fd/N` is the file itself.
int _descriptorMode(DynamicLibrary libc, int fd, String path) {
  final abi = Abi.current();
  if (abi != Abi.macosArm64 && abi != Abi.macosX64) {
    return File('/dev/fd/$fd').statSync().mode & 0xFFF;
  }
  // Intel's plain `fstat` is the old 32-bit-inode layout; `$INODE64` is
  // the one whose st_mode follows the 4-byte st_dev, as on Apple silicon.
  final fstat = libc
      .lookupFunction<
        Int32 Function(Int32, Pointer<Uint8>),
        int Function(int, Pointer<Uint8>)
      >(abi == Abi.macosX64 ? r'fstat$INODE64' : 'fstat');
  final stat = calloc<Uint8>(256); // struct stat is 144 bytes
  try {
    if (fstat(fd, stat) != 0) {
      throw FileSystemException('could not read the file mode', path);
    }
    return (stat + 4).cast<Uint16>().value & 0xFFF;
  } finally {
    calloc.free(stat);
  }
}

/// O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC for this platform, or
/// null when it is not known.
int? _flags() {
  final os = _osFlags();
  if (os == null) return null;
  const wronly = 1;
  return wronly | os.creat | os.excl | os.nofollow | os.cloexec;
}

/// The open flags this platform uses, or null when they are not known. The
/// Linux value of O_NOFOLLOW depends on the architecture, so each one is named
/// and any other is refused.
({int creat, int excl, int nofollow, int cloexec, int nonblock})? _osFlags() {
  final abi = Abi.current();
  if (abi == Abi.macosArm64 || abi == Abi.macosX64) {
    return (
      creat: 0x200,
      excl: 0x800,
      nofollow: 0x100,
      cloexec: 0x1000000,
      nonblock: 0x4,
    );
  }
  if (abi == Abi.linuxX64 || abi == Abi.linuxIA32) {
    return (
      creat: 0x40,
      excl: 0x80,
      nofollow: 0x20000,
      cloexec: 0x80000,
      nonblock: 0x800,
    );
  }
  if (abi == Abi.linuxArm64 || abi == Abi.linuxArm) {
    return (
      creat: 0x40,
      excl: 0x80,
      nofollow: 0x8000,
      cloexec: 0x80000,
      nonblock: 0x800,
    );
  }
  return null;
}
