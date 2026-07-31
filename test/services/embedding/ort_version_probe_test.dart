import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:math' as math;

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/embedding/native_embedding_engine.dart';

String loadedModulePath(String name) {
  final k32 = DynamicLibrary.open('kernel32.dll');
  final getHandle = k32.lookupFunction<
      Pointer<Void> Function(Pointer<Utf16>),
      Pointer<Void> Function(Pointer<Utf16>)>('GetModuleHandleW');
  final getFileName = k32.lookupFunction<
      Uint32 Function(Pointer<Void>, Pointer<Utf16>, Uint32),
      int Function(Pointer<Void>, Pointer<Utf16>, int)>('GetModuleFileNameW');
  final namePtr = name.toNativeUtf16();
  final raw = calloc<Uint16>(4096);
  final buf = raw.cast<Utf16>();
  final h = getHandle(namePtr);
  if (h == nullptr) {
    calloc.free(namePtr);
    calloc.free(raw);
    return '<onnxruntime.dll NOT loaded in process>';
  }
  final len = getFileName(h, buf, 4096);
  final path =
      len > 0 ? buf.toDartString(length: len) : '<name lookup failed>';
  calloc.free(namePtr);
  calloc.free(raw);
  return path;
}

void main() {
  test('probe loaded ORT + worst-case drift across all golden cases', () async {
    final files = NativeEmbeddingEngine.resolveModelFiles(null);
    expect(files, isNotNull, reason: 'nomic model must be on disk');
    final ortLib = Platform.environment['FP_ORT_LIB'] ?? '<unset>';
    print('FP_ORT_LIB=$ortLib');

    final fixture =
        jsonDecode(
              File(
                'test/services/embedding/goldens/nomic_v15_rust_goldens.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    final cases = (fixture['cases'] as List).cast<Map<String, dynamic>>();
    print('golden cases=${cases.length}');

    final engine = NativeEmbeddingEngine();
    try {
      final first = await engine.embed(
        modelPath: files!.model,
        vocabPath: files.vocab,
        text: 'probe',
      );
      print(
        'LOADED onnxruntime.dll => ${loadedModulePath('onnxruntime.dll')}',
      );
      print('dims=${first.length}');

      var worstCosine = 1.0, worstMaxAbs = 0.0;
      String? worstLabel;
      for (final c in cases) {
        final text = c['text'] as String;
        final golden = (c['embedding'] as List)
            .map((e) => (e as num).toDouble())
            .toList();
        final got = await engine.embed(
          modelPath: files.model,
          vocabPath: files.vocab,
          text: text,
        );
        var dot = 0.0, maxAbs = 0.0;
        for (var i = 0; i < golden.length; i++) {
          dot += got[i] * golden[i];
          maxAbs = math.max(maxAbs, (got[i] - golden[i]).abs());
        }
        if (dot < worstCosine) {
          worstCosine = dot;
          worstMaxAbs = maxAbs;
          worstLabel = text.length > 60 ? '${text.substring(0, 60)}…' : text;
        }
      }
      print(
        'worst cosine=$worstCosine maxAbs=$worstMaxAbs label="$worstLabel"',
      );
    } finally {
      engine.shutdown();
    }
  });
}
