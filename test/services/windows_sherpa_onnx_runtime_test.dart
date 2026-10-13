// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final olderRuntime = Platform.environment['FP_TEST_OLD_ORT'];
  final sherpaDirectory = Platform.environment['FP_TEST_SHERPA_DIR'];
  final nativeSkip =
      !Platform.isWindows || olderRuntime == null || sherpaDirectory == null
      ? 'Set FP_TEST_OLD_ORT and FP_TEST_SHERPA_DIR to real Windows DLL fixtures.'
      : false;

  test(
    'rejects an already loaded older runtime before Sherpa binding',
    () async {
      final result = await _run(sherpaDirectory!, preload: olderRuntime);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      expect(result.stdout, contains('REJECTED:'));
      expect(result.stdout, contains('API 28'));
    },
    skip: nativeSkip,
  );

  test('preloads and accepts the bundled matching runtime', () async {
    final result = await _run(sherpaDirectory!, accept: true);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    expect(result.stdout, contains('ACCEPTED'));
  }, skip: nativeSkip);

  test('accepts another ONNX consumer before and after Sherpa', () async {
    final result = await _run(sherpaDirectory!, accept: true, coexist: true);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    expect(result.stdout, contains('COEXISTED'));
  }, skip: nativeSkip);

  test('rejects a missing bundled runtime before loading Sherpa', () async {
    final empty = await Directory.systemTemp.createTemp('fp-missing-ort-');
    try {
      final result = await _run(empty.path);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      expect(result.stdout, contains('REJECTED:'));
      expect(result.stdout, contains('onnxruntime.dll'));
    } finally {
      await empty.delete(recursive: true);
    }
  }, skip: nativeSkip);

  test('rejects an older runtime bundled beside Sherpa', () async {
    final directory = await Directory.systemTemp.createTemp('fp-older-ort-');
    try {
      await File(olderRuntime!).copy('${directory.path}/onnxruntime.dll');
      final result = await _run(directory.path);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      expect(result.stdout, contains('REJECTED:'));
      expect(result.stdout, contains('API 28'));
    } finally {
      await directory.delete(recursive: true);
    }
  }, skip: nativeSkip);
}

Future<ProcessResult> _run(
  String directory, {
  String? preload,
  bool accept = false,
  bool coexist = false,
}) async {
  final temporary = await Directory.systemTemp.createTemp('fp-runtime-check-');
  try {
    final script = File('${temporary.path}/probe.dart');
    await script.writeAsString('''
import 'dart:ffi';
import 'dart:io';
import 'package:front_porch_ai/services/sherpa_runtime.dart';
import 'package:onnxruntime_v2/src/ort_env.dart';
void main(List<String> args) {
  if (args.length > 1) DynamicLibrary.open(args[1]);
  try {
    if ($coexist) {
      DynamicLibrary.open(Platform.environment['FP_SHERPA_LIB']! + '/onnxruntime.dll');
      OrtEnv.instance.init();
    }
    initSherpaBindings();
    if (args[0] != 'accept') throw Exception('Expected runtime rejection before Sherpa binding');
    if ($coexist) {
      OrtEnv.instance.release();
      OrtEnv.instance.init();
      OrtEnv.instance.release();
      print('COEXISTED');
    }
    print('ACCEPTED');
  } on StateError catch (error) {
    if (args[0] == 'accept') rethrow;
    print('REJECTED: \$error');
  }
}
''');
    final flutterRoot = Platform.environment['FLUTTER_ROOT'];
    final dart =
        Platform.environment['FP_TEST_DART'] ??
        (flutterRoot == null
            ? 'dart'
            : '$flutterRoot/bin/cache/dart-sdk/bin/dart.exe');
    return await Process.run(
      dart,
      [
        '--packages=${File('.dart_tool/package_config.json').absolute.path}',
        script.path,
        accept ? 'accept' : 'reject',
        ?preload,
      ],
      environment: {'FP_SHERPA_LIB': directory},
    );
  } finally {
    await temporary.delete(recursive: true);
  }
}
