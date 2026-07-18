// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

/// Thrown when libfpzip is not present — the caller (native DT client) falls
/// back to the Python sidecar, so a missing library degrades gracefully.
class DtFpzipUnavailableException implements Exception {
  final String message;
  DtFpzipUnavailableException(this.message);
  @override
  String toString() => 'DtFpzipUnavailableException: $message';
}

/// Result of an fpzip decompression: dims straight from the fpzip stream
/// header (Draw Things tensors arrive as nf=1, nz=H, ny=W, nx=C; x fastest,
/// i.e. C-order (H, W, C)) plus the float32 payload.
class FpzipResult {
  final int nx, ny, nz, nf;
  final Float32List data;
  FpzipResult(this.nx, this.ny, this.nz, this.nf, this.data);
}

// fpzip 1.3 public C API (fpzip.h). FPZ is a public struct whose leading
// fields are six ints; the library allocates it, we only read/write fields.
final class _FPZ extends Struct {
  @Int32()
  external int type; // 0 = float, 1 = double
  @Int32()
  external int prec;
  @Int32()
  external int nx;
  @Int32()
  external int ny;
  @Int32()
  external int nz;
  @Int32()
  external int nf;
}

typedef _ReadFromBufferC = Pointer<_FPZ> Function(Pointer<Void>);
typedef _ReadHeaderC = Int32 Function(Pointer<_FPZ>);
typedef _ReadHeaderD = int Function(Pointer<_FPZ>);
typedef _ReadC = IntPtr Function(Pointer<_FPZ>, Pointer<Void>);
typedef _ReadD = int Function(Pointer<_FPZ>, Pointer<Void>);
typedef _ReadCloseC = Void Function(Pointer<_FPZ>);
typedef _ReadCloseD = void Function(Pointer<_FPZ>);

/// FFI binding to libfpzip (LLNL predictive float compressor) — decode only.
/// Build the dylib on macOS with `scripts/build-fpzip-macos.sh`; in release
/// bundles it ships in Contents/Frameworks/. Lazily loaded; all callers get
/// [DtFpzipUnavailableException] when no library can be found so they can
/// fall back to the Python sidecar path.
class DtFpzip {
  DtFpzip._();
  static final DtFpzip instance = DtFpzip._();

  DynamicLibrary? _lib;
  String? _loadError;

  static String get _libName => Platform.isWindows
      ? 'fpzip.dll'
      : (Platform.isMacOS ? 'libfpzip.dylib' : 'libfpzip.so');

  /// Candidate locations, most specific first. FP_FPZIP_LIB always wins so
  /// dev/test setups can point anywhere.
  static List<String> candidatePaths() {
    final paths = <String>[];
    final env = Platform.environment['FP_FPZIP_LIB'];
    if (env != null && env.isNotEmpty) paths.add(env);
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    if (Platform.isMacOS) {
      // .app bundle: Contents/MacOS/<exe> → Contents/Frameworks/
      paths.add(p.join(File(exeDir).parent.path, 'Frameworks', _libName));
    }
    paths.add(p.join(exeDir, _libName));
    // Dev (`flutter run` from the repo): walk up looking for tools/fpzip/.
    var dir = Directory.current;
    for (var i = 0; i < 8; i++) {
      paths.add(p.join(dir.path, 'tools', 'fpzip', _libName));
      final parent = dir.parent;
      if (parent.path == dir.path) break;
      dir = parent;
    }
    return paths;
  }

  DynamicLibrary _load() {
    final cached = _lib;
    if (cached != null) return cached;
    if (_loadError != null) throw DtFpzipUnavailableException(_loadError!);
    for (final path in candidatePaths()) {
      if (!File(path).existsSync()) continue;
      try {
        final lib = DynamicLibrary.open(path);
        _lib = lib;
        return lib;
      } catch (e) {
        _loadError = 'Failed to load $path: $e';
      }
    }
    _loadError ??=
        'libfpzip not found (looked in FP_FPZIP_LIB, app Frameworks, '
        'executable dir, tools/fpzip). Build it with '
        'scripts/build-fpzip-macos.sh for native Draw Things decode.';
    throw DtFpzipUnavailableException(_loadError!);
  }

  /// Whether the library can be loaded (used to pre-flight the native path).
  bool get isAvailable {
    try {
      _load();
      return true;
    } on DtFpzipUnavailableException {
      return false;
    }
  }

  /// Decompress a single-precision fpzip stream. Throws [FormatException] on
  /// malformed streams and [DtFpzipUnavailableException] when no library.
  FpzipResult decompress(Uint8List compressed) {
    final lib = _load();
    final readFromBuffer = lib
        .lookupFunction<_ReadFromBufferC, _ReadFromBufferC>(
          'fpzip_read_from_buffer',
        );
    final readHeader = lib.lookupFunction<_ReadHeaderC, _ReadHeaderD>(
      'fpzip_read_header',
    );
    final read = lib.lookupFunction<_ReadC, _ReadD>('fpzip_read');
    final readClose = lib.lookupFunction<_ReadCloseC, _ReadCloseD>(
      'fpzip_read_close',
    );

    final buf = calloc<Uint8>(compressed.length);
    Pointer<Float>? out;
    Pointer<_FPZ>? fpz;
    try {
      buf.asTypedList(compressed.length).setAll(0, compressed);
      fpz = readFromBuffer(buf.cast());
      if (fpz == nullptr) {
        throw const FormatException('fpzip_read_from_buffer failed');
      }
      if (readHeader(fpz) == 0) {
        throw const FormatException('fpzip: invalid stream header');
      }
      final f = fpz.ref;
      if (f.type != 0) {
        throw const FormatException('fpzip: expected float32 stream');
      }
      final count = f.nx * f.ny * f.nz * f.nf;
      if (count <= 0 || count > 500 * 1024 * 1024) {
        throw FormatException('fpzip: implausible element count $count');
      }
      out = calloc<Float>(count);
      final consumed = read(fpz, out.cast());
      if (consumed == 0) {
        throw const FormatException('fpzip: decompression failed');
      }
      final data = Float32List.fromList(out.asTypedList(count));
      return FpzipResult(f.nx, f.ny, f.nz, f.nf, data);
    } finally {
      if (fpz != null && fpz != nullptr) readClose(fpz);
      if (out != null) calloc.free(out);
      calloc.free(buf);
    }
  }
}
