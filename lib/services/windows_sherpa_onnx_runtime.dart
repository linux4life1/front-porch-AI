// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

// sherpa_onnx 1.13.8 requests this API before constructing native engines.
const _requiredOrtApi = 28;
const _loadLibrarySearchDllLoadDir = 0x100;
const _loadLibrarySearchDefaultDirs = 0x1000;

typedef _GetApiNative = Pointer<Void> Function(Uint32);
typedef _GetVersionNative = Pointer<Utf8> Function();

final class _OrtApiBase extends Struct {
  external Pointer<NativeFunction<_GetApiNative>> getApi;
  external Pointer<NativeFunction<_GetVersionNative>> getVersionString;
}

/// Reject incompatible process runtimes before Sherpa can dereference GetApi.
/// A previously loaded DLL takes precedence over the bundled copy on Windows.
void ensureWindowsSherpaOnnxRuntime(String? sherpaDirectory) {
  if (!Platform.isWindows) {
    return;
  }
  final kernel = DynamicLibrary.open('kernel32.dll');
  final moduleHandle = kernel
      .lookupFunction<
        Pointer<Void> Function(Pointer<Utf16>),
        Pointer<Void> Function(Pointer<Utf16>)
      >('GetModuleHandleW');
  final loadLibrary = kernel
      .lookupFunction<
        Pointer<Void> Function(Pointer<Utf16>, Pointer<Void>, Uint32),
        Pointer<Void> Function(Pointer<Utf16>, Pointer<Void>, int)
      >('LoadLibraryExW');
  final getProcAddress = kernel
      .lookupFunction<
        Pointer<Void> Function(Pointer<Void>, Pointer<Utf8>),
        Pointer<Void> Function(Pointer<Void>, Pointer<Utf8>)
      >('GetProcAddress');
  final moduleFilename = kernel
      .lookupFunction<
        Uint32 Function(Pointer<Void>, Pointer<Utf16>, Uint32),
        int Function(Pointer<Void>, Pointer<Utf16>, int)
      >('GetModuleFileNameW');
  final basename = 'onnxruntime.dll'.toNativeUtf16();
  final symbol = 'OrtGetApiBase'.toNativeUtf8();
  final filename = calloc<Uint16>(32768).cast<Utf16>();
  try {
    void validate(Pointer<Void> handle) {
      final length = moduleFilename(handle, filename, 32768);
      final actual = length == 0
          ? 'loaded onnxruntime.dll'
          : filename.toDartString(length: length);
      final address = getProcAddress(handle, symbol);
      if (address == nullptr) {
        throw StateError(
          'Windows Sherpa requires ONNX Runtime API '
          '$_requiredOrtApi, but $actual does not export OrtGetApiBase. '
          'Reinstall the matching application runtime and restart.',
        );
      }
      final base = address
          .cast<NativeFunction<Pointer<_OrtApiBase> Function()>>()
          .asFunction<Pointer<_OrtApiBase> Function()>()();
      if (base == nullptr || base.ref.getApi == nullptr) {
        throw StateError(
          'Windows Sherpa requires ONNX Runtime API '
          '$_requiredOrtApi, but $actual has no usable API base.',
        );
      }
      final api = base.ref.getApi.asFunction<Pointer<Void> Function(int)>()(
        _requiredOrtApi,
      );
      if (api == nullptr) {
        final version = base.ref.getVersionString == nullptr
            ? 'unknown'
            : base.ref.getVersionString
                  .asFunction<Pointer<Utf8> Function()>()()
                  .toDartString();
        throw StateError(
          'Windows Sherpa requires ONNX Runtime API '
          '$_requiredOrtApi, but $actual (version $version) is incompatible. '
          'Reinstall the matching application runtime and restart.',
        );
      }
    }

    var loaded = moduleHandle(basename);
    if (loaded != nullptr) {
      validate(loaded);
      return;
    }
    if (sherpaDirectory == null) {
      throw StateError(
        'Windows Sherpa requires a bundled onnxruntime.dll '
        'supporting API $_requiredOrtApi beside sherpa-onnx-c-api.dll. '
        'The native library directory was not found.',
      );
    }
    final runtime = File(p.join(sherpaDirectory, 'onnxruntime.dll')).absolute;
    if (!runtime.existsSync()) {
      throw StateError(
        'Windows Sherpa requires onnxruntime.dll supporting '
        'API $_requiredOrtApi at ${runtime.path}, but the file is missing.',
      );
    }
    final path = runtime.path.toNativeUtf16();
    Pointer<Void> selected;
    try {
      // Search this DLL's directory and Windows default directories only.
      selected = loadLibrary(
        path,
        nullptr,
        _loadLibrarySearchDllLoadDir | _loadLibrarySearchDefaultDirs,
      );
    } finally {
      calloc.free(path);
    }
    if (selected == nullptr) {
      throw StateError(
        'Windows Sherpa could not load ${runtime.path}. '
        'Install the matching ONNX Runtime and its required dependencies.',
      );
    }
    // Another isolate may have loaded the basename while we were preloading.
    // Validate the process-selected module as well as the absolute-path handle.
    loaded = moduleHandle(basename);
    if (loaded == nullptr) {
      throw StateError(
        'Windows Sherpa could not locate loaded onnxruntime.dll.',
      );
    }
    validate(loaded);
    if (selected != loaded) {
      validate(selected);
    }
    // Keep the module loaded for Sherpa and other in-process ONNX consumers.
  } finally {
    calloc.free(filename);
    calloc.free(symbol);
    calloc.free(basename);
  }
}
