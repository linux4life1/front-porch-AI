// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Progress update from image generation
class ImageGenProgress {
  final int step;
  final int totalSteps;
  final String message;

  const ImageGenProgress(this.step, this.totalSteps, {this.message = ''});
}

/// Draw Things gRPC service - uses Python client as bridge
class DrawThingsGrpcService {
  final String host;
  final int port;
  final String pythonPath;
  final String pythonClientDir;

  DrawThingsGrpcService({
    required this.host,
    this.port = 7859,
    String? pythonPath,
    String? pythonClientDir,
  })  : pythonPath = pythonPath ?? _resolvePythonPath(),
        pythonClientDir = pythonClientDir ?? _resolvePythonClientDir() {
    debugPrint('DrawThingsGrpcService: Resolved pythonPath: ${this.pythonPath}');
    debugPrint('DrawThingsGrpcService: Resolved pythonClientDir: ${this.pythonClientDir}');
  }

  static String _resolvePythonPath() {
    if (Platform.isMacOS) {
      // Check common absolute paths for python3 on macOS
      final candidates = [
        '/usr/bin/python3',
        '/usr/local/bin/python3',
        '/opt/homebrew/bin/python3',
      ];
      for (final path in candidates) {
        if (File(path).existsSync()) return path;
      }
    }
    // Fallback to searching the system PATH
    return 'python3';
  }

  static String _resolvePythonClientDir() {
    if (Platform.isMacOS) {
      final execPath = Platform.resolvedExecutable;
      final execDir = File(execPath).parent.path;

      // 1. Check for bundled Resources in macOS App Bundle
      // Structure: App.app/Contents/MacOS/Executable -> App.app/Contents/Resources/
      final bundleResources = p.join(Directory(execDir).parent.path, 'Resources', 'dt-grpc-python');
      if (Directory(bundleResources).existsSync()) {
        return bundleResources;
      }

      // 2. Dev mode: Search upwards from executable for the project root folder
      var dir = Directory(execDir);
      for (int i = 0; i < 10; i++) {
        // Priority 1: Vendored tools directory
        final toolsCandidate = Directory(p.join(dir.path, 'tools', 'dt-grpc-python'));
        if (toolsCandidate.existsSync()) {
          return toolsCandidate.path;
        }
        // Priority 2: Direct folder in root
        final directCandidate = Directory(p.join(dir.path, 'dt-grpc-python'));
        if (directCandidate.existsSync()) {
          return directCandidate.path;
        }
        final parent = dir.parent;

        if (parent.path == dir.path) break;
        dir = parent;
      }
    }

    // 3. Final fallback to the original dev path
    return '/tmp/dt-grpc-python';
  }


  /// Tests connection to Draw Things via Python client
  Future<bool> testConnection() async {
    try {
      var script = '''
import sys
sys.path.insert(0, 'PYTHON_CLIENT_DIR')
from client import DrawThingsClient
client = DrawThingsClient('HOST', PORT)
try:
    result = client.echo('test')
    print('OK')
    sys.exit(0)
except Exception as e:
    print(str(e))
    sys.exit(1)
finally:
    client.close()
''';
      script = script.replaceAll('PYTHON_CLIENT_DIR', pythonClientDir);
      script = script.replaceAll('HOST', host);
      script = script.replaceAll('PORT', port.toString());

      final scriptFile = await _writePythonScript(script);
      debugPrint('DrawThingsGrpcService: Script:\n$script');
      
      final result = await _runWithTimeout(
        pythonPath,
        [scriptFile.path],
        const Duration(seconds: 30),
      );
      debugPrint('DrawThingsGrpcService: Exit code: ${result.exitCode}');
      debugPrint('DrawThingsGrpcService: Stdout: ${result.stdout}');
      debugPrint('DrawThingsGrpcService: Stderr: ${result.stderr}');
      await scriptFile.delete();

      if (result.exitCode == 0 && result.stdout.toString().trim() == 'OK') {
        debugPrint('DrawThingsGrpcService: Connection test passed');
        return true;
      } else {
        debugPrint('DrawThingsGrpcService: Connection test failed: ${result.stdout}');
        return false;
      }
    } catch (e) {
      debugPrint('DrawThingsGrpcService: Connection test error: $e');
      return false;
    }
  }

  /// Fetches available checkpoint models from Draw Things
  Future<List<String>> fetchModels() async {
    try {
      var script = '''
import sys, json
sys.path.insert(0, 'PYTHON_CLIENT_DIR')
from client import DrawThingsClient
import imageService_pb2 as pb2

client = DrawThingsClient('HOST', PORT)
try:
    client._connect()
    response = client._stub.Echo(pb2.EchoRequest(name='models'))
    files = []
    for f in response.files:
        lower = f.lower()
        if any(x in lower for x in ['lora', 'controlnet', 'clip', 't5', 'encoder', 'gemma', 'llama', 'mistral', 'qwen', 'phi', 'chroma', 'ltx', 'vicuna', 'alpaca']):
            continue
        if f.endswith('.ckpt'):
            files.append(f)
    print(json.dumps(files))
except Exception as e:
    print('[]')
finally:
    client.close()
''';
      script = script.replaceAll('PYTHON_CLIENT_DIR', pythonClientDir);
      script = script.replaceAll('HOST', host);
      script = script.replaceAll('PORT', port.toString());

      final scriptFile = await _writePythonScript(script);

      final result = await _runWithTimeout(
        pythonPath,
        [scriptFile.path],
        const Duration(seconds: 30),
      );
      await scriptFile.delete();

      if (result.exitCode == 0) {
        final files = jsonDecode(result.stdout.toString()) as List;
        final checkpoints = files.cast<String>();
        debugPrint('DrawThingsGrpcService: Fetched ${checkpoints.length} models');
        return checkpoints;
      } else {
        debugPrint('DrawThingsGrpcService: fetchModels failed: ${result.stdout}');
        return [];
      }
    } catch (e) {
      debugPrint('DrawThingsGrpcService: fetchModels error: $e');
      return [];
    }
  }

  /// Generates an image via Python client bridge
  Future<Uint8List> generateImage({
    required String prompt,
    String negativePrompt = '',
    String model = '',
    int width = 1024,
    int height = 1024,
    int steps = 20,
    double cfgScale = 7.0,
    int seed = -1,
    Function(ImageGenProgress)? onProgress,
  }) async {
    final tempRoot = await getTemporaryDirectory();
    final requestId = DateTime.now().millisecondsSinceEpoch;
    final tempDir = await Directory(p.join(tempRoot.path, 'dt_gen_$requestId')).create(recursive: true);
    final outputPath = p.join(tempDir.path, 'output.png');

    debugPrint('DrawThingsGrpcService: Output path will be: $outputPath');

    var script = r'''
import sys, json, os
sys.path.insert(0, 'PYTHON_CLIENT_DIR')
from client import DrawThingsClient, GenerationConfig, Sampler, SeedMode

client = DrawThingsClient('HOST', PORT)
try:
    config = GenerationConfig(
        model='MODEL',
        start_width=WIDTH_DIV64,
        start_height=HEIGHT_DIV64,
        seed=SEED,
        steps=STEPS,
        guidance_scale=CFG_SCALE,
        strength=1.0,
        shift=3.0,
        sampler=Sampler.DDIM_TRAILING,
        seed_mode=SeedMode.SCALE_ALIKE,
        refiner_start=0.1,
        resolution_dependent_shift=False,
        mask_blur=1.5,
        sharpness=0.0,
    )
    
    result = client.generate(
        config=config,
        prompt='PROMPT',
        negative_prompt='NEGATIVE_PROMPT',
        verbose=True,
    )
    
    if result.images:
        # Use result.save() which handles NNC tensor decoding if needed
        out_path = 'OUTPUT_PATH'
        result.save(out_path)
        
        if os.path.exists(out_path):
            file_size = os.path.getsize(out_path)
            print(f'FILE_SIZE:{file_size}')
            print('SUCCESS')
        else:
            print('ERROR: File was not written to ' + out_path)
    else:
        print('NO_IMAGE')
except Exception as e:
    print('ERROR: ' + str(e))
finally:
    client.close()
''';


    // Robust escaping for Python string literals
    final escapedPrompt = prompt.replaceAll('\\', '\\\\').replaceAll("'", "\\'").replaceAll('\n', ' ');
    final escapedNegative = negativePrompt.replaceAll('\\', '\\\\').replaceAll("'", "\\'").replaceAll('\n', ' ');

    final replacements = {
      'PYTHON_CLIENT_DIR': pythonClientDir,
      'HOST': host,
      'PORT': port.toString(),
      'MODEL': model,
      'WIDTH_DIV64': (width ~/ 64).toString(),
      'HEIGHT_DIV64': (height ~/ 64).toString(),
      'SEED': (seed == -1 ? 0 : seed).toString(),
      'STEPS': steps.toString(),
      'CFG_SCALE': cfgScale.toString(),
      'PROMPT': escapedPrompt,
      'NEGATIVE_PROMPT': escapedNegative,
      'OUTPUT_PATH': outputPath,
    };

    replacements.forEach((key, value) {
      script = script.replaceAll(key, value);
    });

    debugPrint('DrawThingsGrpcService: Generated Python script:\n$script');

    final scriptFile = await _writePythonScript(script);

    try {
      final result = await _runWithTimeout(
        pythonPath,
        [scriptFile.path],
        const Duration(seconds: 300),
      );

      debugPrint('DrawThingsGrpcService: Python exit code: ${result.exitCode}');
      debugPrint('DrawThingsGrpcService: Python stdout: ${result.stdout}');
      if (result.stderr.isNotEmpty) {
        debugPrint('DrawThingsGrpcService: Python stderr: ${result.stderr}');
      }

      // Cleanup script file immediately
      try {
        await scriptFile.delete();
        final scriptDir = scriptFile.parent;
        if (await scriptDir.exists()) {
          await scriptDir.delete(recursive: true);
        }
      } catch (_) {}

      if (result.exitCode != 0 || !result.stdout.toString().contains('SUCCESS')) {
        throw Exception('Generation failed: ${result.stdout}');
      }

      final file = File(outputPath);
      if (!await file.exists()) {
        throw Exception('Output file not created at $outputPath');
      }

      final fileSize = await file.length();
      debugPrint('DrawThingsGrpcService: Output file size: $fileSize bytes');
      
      if (fileSize == 0) {
        throw Exception('Output file is empty after Python generation');
      }

      // Read bytes
      final bytes = await file.readAsBytes();
      debugPrint('DrawThingsGrpcService: Successfully read ${bytes.length} bytes');

      // Debug: Print first 16 bytes to check header
      if (bytes.length >= 16) {
        final header = bytes.sublist(0, 16).map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
        debugPrint('DrawThingsGrpcService: First 16 bytes: $header');
      }

      return bytes;
    } catch (e) {
      debugPrint('DrawThingsGrpcService: Error during generation: $e');
      rethrow;
    } finally {
      // Always cleanup the generation temp directory
      try {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
          debugPrint('DrawThingsGrpcService: Cleaned up temp directory');
        }
      } catch (e) {
        debugPrint('DrawThingsGrpcService: Cleanup failed: $e');
      }
    }
  }

  Future<File> _writePythonScript(String content) async {
    final tempRoot = await getTemporaryDirectory();
    final requestId = DateTime.now().millisecondsSinceEpoch;
    final tempDir = await Directory(p.join(tempRoot.path, 'dt_script_$requestId')).create(recursive: true);
    final scriptFile = File(p.join(tempDir.path, 'script.py'));
    await scriptFile.writeAsString(content);
    return scriptFile;
  }

  Future<ProcessResult> _runWithTimeout(
    String executable,
    List<String> arguments,
    Duration timeout,
  ) async {
    final process = await Process.start(executable, arguments);
    final stdoutFuture = process.stdout.transform(utf8.decoder).join();
    final stderrFuture = process.stderr.transform(utf8.decoder).join();
    final exitCode = await process.exitCode.timeout(timeout);
    
    // Await both streams before returning
    final stdout = await stdoutFuture;
    final stderr = await stderrFuture;
    
    return ProcessResult(process.pid, exitCode, stdout, stderr);
  }

}
