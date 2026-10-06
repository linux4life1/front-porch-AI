// Auto mode and the slot keeper: for an ordinary model the app keeps the
// chats itself, so no smart cache is written and context shift stays on;
// a model with recurrent layers keeps KoboldCpp's own cache; and when the
// keeper failed for a model on an engine version, the next start there goes
// back to the smart cache auto mode wrote before. The models are real
// headers grown to their real size (sparse files, so nothing is written).

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/models/hardware_info.dart';
import 'package:front_porch_ai/services/kobold/kobold.dart';
import 'package:front_porch_ai/services/kobold_launch_args.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/utils/utils.dart';

import '../kobold_service_test.dart'
    show createStorageService, setupPathProviderMock;

const _fixtures = 'test/fixtures/gguf_headers';

Future<String> _model(Directory dir, String fixture) async {
  final side =
      jsonDecode(File('$_fixtures/$fixture.json').readAsStringSync()) as Map;
  final file = File(p.join(dir.path, '$fixture.gguf'));
  final raf = await file.open(mode: FileMode.write);
  await raf.writeFrom(File('$_fixtures/$fixture.gguf').readAsBytesSync());
  await raf.setPosition((side['fixture_file_bytes'] as int) - 1);
  await raf.writeByte(0);
  await raf.close();
  return file.path;
}

({GGUFModelInfo info, int bytes}) _header(String name) {
  final side =
      (jsonDecode(File('$_fixtures/$name.json').readAsStringSync()) as Map)
          .cast<String, dynamic>();
  final bytes = side['fixture_file_bytes'] as int;
  final header = GGUFFileReader.parseHeaderBytes(
    File('$_fixtures/$name.gguf').readAsBytesSync(),
  )!;
  return (
    info: GGUFParser.modelInfoFromHeader(header, fileSize: bytes)!,
    bytes: bytes,
  );
}

HardwareInfo _nvidia(int vramMb, int ramMb) => HardwareInfo(
  gpuName: 'NVIDIA GeForce RTX 4080',
  vramMb: vramMb,
  ramMb: ramMb,
  vendor: 'Nvidia',
  hasCuda: true,
);

KoboldAutoTuning _tune(
  String name,
  KoboldMachine machine, {
  KoboldMemoryBackend backend = KoboldMemoryBackend.cuda,
}) {
  final m = _header(name);
  return koboldAutoTuning(
    KoboldFit(
      info: m.info,
      fileSizeBytes: m.bytes,
      contextSize: 16384,
      batchSize: 512,
      backend: backend,
    ),
    machine,
  );
}

const _roomy = KoboldMachine(
  backend: KoboldMemoryBackend.cuda,
  totalGraphicsMb: 16384,
  totalSystemMb: 65536,
  freeGraphicsMb: 16000,
  freeSystemMb: 60000,
);

const _tight = KoboldMachine(
  backend: KoboldMemoryBackend.cuda,
  totalGraphicsMb: 16384,
  totalSystemMb: 8192,
  freeGraphicsMb: 16000,
  freeSystemMb: 5200,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupPathProviderMock();

  late StorageService storage;
  late Directory dir;

  setUp(() async {
    storage = await createStorageService();
    dir = Directory.systemTemp.createTempSync('fpai auto keeper');
  });

  tearDown(() => dir.deleteSync(recursive: true));

  /// The engine in [dir] as a launch finds it: a program with a version
  /// record written for it.
  Future<String> engine(String version) async {
    final exe = File(p.join(dir.path, 'koboldcpp'))
      ..writeAsBytesSync([1, 2, 3]);
    await KoboldBinaryVersion.write(dir.path, version: version, size: 3);
    return exe.path;
  }

  Future<Map<String, dynamic>> launch(
    String model, {
    required HardwareInfo hardware,
    FreeMemoryMb free = (graphics: 16000, system: 60000),
    String? engineVersion,
    void Function(String note)? onNote,
  }) async {
    final args = await buildKoboldLaunchArgs(
      storage: storage,
      executablePath: engineVersion == null
          ? p.join(dir.path, 'koboldcpp')
          : await engine(engineVersion),
      modelPath: model,
      kcppsPath: null,
      mmprojPath: null,
      port: 5001,
      gpuLayers: 0,
      contextSize: 16384,
      useVulkan: false,
      useCublas: true,
      useMetal: false,
      useRocm: false,
      hardware: hardware,
      free: free,
      onNote: onNote,
    );
    return (jsonDecode(
              File(args[args.indexOf('--config') + 1]).readAsStringSync(),
            )
            as Map)
        .cast<String, dynamic>();
  }

  group('what auto mode writes', () {
    test('an ordinary model: no smart cache, context shift on, the batch '
        'still tuned', () async {
      final config = await launch(
        await _model(dir, 'Qwen3-14B'),
        hardware: _nvidia(16384, 65536),
      );

      expect(config.containsKey('smartcache'), isFalse);
      expect(config['noshift'], isFalse);
      // Changed 2026-10-06 (maintainer's ruling): auto mode no longer takes
      // the largest batch that fits; an NVIDIA card starts at 1,024 (512
      // untuned), so this still shows the batch was tuned.
      expect(config['batchsize'], 1024);
    });

    test(
      "a model with recurrent layers keeps KoboldCpp's own smart cache",
      () async {
        final config = await launch(
          await _model(dir, 'Qwen3.6-35B-A3B-Q4_K_XL'),
          hardware: _nvidia(24576, 131072),
          free: (graphics: 24000, system: 120000),
        );

        expect(config['smartcache'], greaterThanOrEqualTo(2));
        expect(config['noshift'], isFalse);
      },
    );

    test('a failure of the keeper for this model on this engine brings the '
        'smart cache back, and the log says why', () async {
      final model = await _model(dir, 'Qwen3-14B');
      await storage.backendSettings.noteKeeperFailed(
        '1.117.1',
        'Qwen3-14B.gguf',
      );
      final notes = <String>[];

      final config = await launch(
        model,
        hardware: _nvidia(16384, 65536),
        engineVersion: '1.117.1',
        onNote: notes.add,
      );

      expect(config['smartcache'], 3);
      expect(config['noshift'], isFalse);
      expect(notes.where((n) => n.contains('smart cache')), hasLength(1));
    });

    test('a failure with another engine version or another model changes '
        'nothing', () async {
      final model = await _model(dir, 'Qwen3-14B');
      await storage.backendSettings.noteKeeperFailed(
        '1.117.1',
        'Qwen3-14B.gguf',
      );
      await storage.backendSettings.noteKeeperFailed(
        '1.122.1',
        'Another-Model.gguf',
      );

      final newer = await launch(
        model,
        hardware: _nvidia(16384, 65536),
        engineVersion: '1.122.1',
      );

      expect(newer.containsKey('smartcache'), isFalse);
    });

    test('a failure is remembered by the next run of the app', () async {
      await storage.backendSettings.noteKeeperFailed('1.117.1', 'M.gguf');

      final again = StorageService();
      await again.initialized;

      expect(
        again.backendSettings.keeperFailedFor('1.117.1', 'M.gguf'),
        isTrue,
      );
      expect(
        again.backendSettings.keeperFailedFor('1.122.1', 'M.gguf'),
        isFalse,
      );
      expect(
        again.backendSettings.keeperFailedFor('1.117.1', 'N.gguf'),
        isFalse,
      );
    });
  });

  group('the keeper in the tuning', () {
    test('an ordinary model with room keeps the most chats KoboldCpp can '
        'save', () {
      final t = _tune('Qwen3-14B', _roomy);

      expect(t.chats, kKoboldSaveSlots);
      expect(t.cacheSetting(keeper: true), (asked: 0, contextShift: true));
      expect(
        t.cacheSetting(keeper: false),
        t.smartCache,
        reason:
            "the smart cache auto mode wrote before is still there to fall "
            'back on',
      );
    });

    test('less memory has room for fewer chats, and none when there is no '
        'room: the open chat is kept all the same', () {
      // A full context of this model is 2,560 MB; its own share of system
      // memory is 511 MB, and 2,048 are set aside.
      expect(_tune('Qwen3-14B', _tight).chats, 1);
      const none = KoboldMachine(
        backend: KoboldMemoryBackend.cuda,
        totalGraphicsMb: 16384,
        totalSystemMb: 4096,
        freeGraphicsMb: 16000,
        freeSystemMb: 3000,
      );
      final t = _tune('Qwen3-14B', none);
      expect(t.chats, 0);
      expect(t.cacheSetting(keeper: true), (asked: 0, contextShift: true));
    });

    test('a model with recurrent layers is never the keeper\'s', () {
      final t = _tune('Qwen3.6-35B-A3B-Q4_K_XL', _roomy);

      expect(t.chats, 0);
      expect(t.cacheSetting(keeper: true), t.smartCache);
    });
  });

  group('what the card says about going back to another chat', () {
    Future<List<String>> lines(
      String model,
      HardwareInfo hw,
      FreeMemoryMb free,
    ) async {
      final m = _header(model);
      return KoboldStatusFacts.of(
        storage: storage,
        hardware: hw,
        free: free,
        info: m.info,
        bytes: m.bytes,
      )!.lines;
    }

    test(
      'quick for an ordinary model when two or more chats are kept',
      () async {
        // Two or more only with recent chats asked for in Settings →
        // Advanced: by default the keeper keeps just the open chat.
        await storage.backendSettings.setKeepRecentChats(1);
        final said = await lines('Qwen3-14B', _nvidia(16384, 65536), (
          graphics: 16000,
          system: 60000,
        ));

        expect(said, contains('Going back to another chat is quick.'));
      },
    );

    test('a moment to catch up when memory keeps fewer than two', () async {
      final said = await lines('Qwen3-14B', _nvidia(16384, 8192), (
        graphics: 16000,
        system: 6000,
      ));

      expect(
        said,
        contains('Going back to another chat takes a moment to catch up.'),
      );
    });
  });
}
