// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The City96 loader update is required for the published Qwen-Image 2.1 GGUF
// pair, and dangerous everywhere else. Every loader here is a temp file; the
// locator is always injected, so no real ComfyUI install is ever looked at.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/services/image/comfy_gguf_city96.dart';
import 'package:front_porch_ai/services/image/comfy_gguf_city96_gate.dart';
import 'package:front_porch_ai/services/image/comfy_model_paths.dart';

import 'city96_test_loader.dart';
import 'city96_test_probe.dart';

Map<String, dynamic> _graph({
  String unet = 'qwen-image-2.1-Q2_K.gguf',
  String clip = 'Qwen3-VL-8B-Instruct-Q4_K_M.gguf',
}) {
  return {
    '1': {
      'class_type': 'UnetLoaderGGUF',
      'inputs': {'unet_name': unet},
    },
    '2': {
      'class_type': 'CLIPLoaderGGUF',
      'inputs': {'clip_name': clip, 'type': 'qwen_image'},
    },
    '3': {
      'class_type': 'KSampler',
      'inputs': {'seed': 1},
    },
  };
}

void main() {
  late Directory dir;
  late File loader;
  late List<City96Question> asked;
  var answer = true;
  var located = 0;

  /// The id of the ComfyUI process, as a scan would report it.
  var comfyPid = 100;

  City96Gate gate({bool withAsker = true, File? at}) {
    return City96Gate(
      // The OS is never asked: the ids here belong to no real process.
      probe: const FakeProbe(),
      pidFor: (_) async => comfyPid,
      locate: (_) async {
        located++;
        return at ?? loader;
      },
      ask: withAsker
          ? (q) async {
              asked.add(q);
              return answer;
            }
          : null,
    );
  }

  setUp(() {
    dir = Directory.systemTemp.createTempSync('city96-gate');
    addTearDown(() => dir.deleteSync(recursive: true));
    loader = File(p.join(dir.path, 'loader.py'))
      ..writeAsStringSync(kStockCity96Loader);
    asked = [];
    answer = true;
    located = 0;
    comfyPid = 100;
  });

  group('(a) only the posted Qwen-Image 2.1 GGUF pair triggers it', () {
    test('the 2.1 GGUF unet and the Qwen3-VL GGUF encoder each count', () {
      expect(graphNeedsCity96Patch(_graph()), isTrue);
      expect(
        graphNeedsCity96Patch(_graph(clip: 'qwen_3_4b.safetensors')),
        isTrue,
      );
      expect(
        graphNeedsCity96Patch(_graph(unet: 'flux1-dev-Q4_K.gguf')),
        isTrue,
      );
    });

    test('a qwen_3_4b encoder never counts, GGUF or not', () {
      for (final clip in [
        'qwen_3_4b.gguf',
        'qwen_3_4b.safetensors',
        'Qwen3-4B-Q8_0.gguf',
        'qwen3_8b.gguf',
      ]) {
        expect(
          graphNeedsCity96Patch(
            _graph(unet: 'z-image-turbo-Q5_K_M.gguf', clip: clip),
          ),
          isFalse,
          reason: clip,
        );
      }
    });

    test('other Qwen and GGUF models never count', () {
      for (final unet in [
        'qwen-image-Q4_K.gguf',
        'qwen_image_2512_Q4.gguf',
        'qwen-image-2.1.safetensors',
        'qwen-image-edit-2511-Q4.gguf',
        'flux1-schnell-Q2_K.gguf',
      ]) {
        expect(
          graphNeedsCity96Patch(_graph(unet: unet, clip: 'qwen_2.5_vl.gguf')),
          isFalse,
          reason: unet,
        );
      }
    });

    test('an mmproj file is not the encoder', () {
      expect(
        isQwen3VlGgufEncoder('mmproj-Qwen3-VL-8B-Instruct-F16.gguf'),
        isFalse,
      );
    });

    test('a graph that does not use the pair is never looked at', () async {
      final result = await gate().ensure(
        comfyUrl: 'http://127.0.0.1:8188',
        graph: _graph(unet: 'z-image.gguf', clip: 'qwen_3_4b.gguf'),
      );
      expect(result.state, City96State.notNeeded);
      expect(located, 0);
      expect(asked, isEmpty);
      expect(loader.readAsStringSync(), kStockCity96Loader);
    });
  });

  group('(b) only the ComfyUI at the configured URL', () {
    test(
      'the loader is found by the running server on that port only',
      () async {
        final mine = Directory(p.join(dir.path, 'mine'));
        final other = Directory(p.join(dir.path, 'other'));
        for (final d in [mine, other]) {
          File(p.join(d.path, 'custom_nodes', 'ComfyUI-GGUF', 'loader.py'))
            ..createSync(recursive: true)
            ..writeAsStringSync(kStockCity96Loader);
        }
        final procs = [
          ComfyProcessSnapshot(
            command: 'python ${p.join(other.path, 'main.py')} --port 8188',
            cwd: other.path,
            pid: 11,
            uid: 1000,
          ),
          ComfyProcessSnapshot(
            command: 'python ${p.join(mine.path, 'main.py')} --port 8190',
            cwd: mine.path,
            pid: 12,
            uid: 1000,
          ),
        ];
        final found = await city96LoaderForUrl(
          'http://127.0.0.1:8190',
          processes: procs,
          probe: const FakeProbe(byPort: {8188: 11, 8190: 12}),
        );
        expect(
          found?.path,
          p.join(mine.path, 'custom_nodes', 'ComfyUI-GGUF', 'loader.py'),
        );
        expect(
          await city96LoaderForUrl(
            'http://127.0.0.1:9999',
            processes: procs,
            probe: const FakeProbe(byPort: {8188: 11, 8190: 12}),
          ),
          isNull,
        );
      },
    );

    test(
      'no running server on that port means no loader, even with installs about',
      () async {
        final install = Directory(p.join(dir.path, 'ComfyUI'));
        File(p.join(install.path, 'custom_nodes', 'ComfyUI-GGUF', 'loader.py'))
          ..createSync(recursive: true)
          ..writeAsStringSync(kStockCity96Loader);
        expect(
          await city96LoaderForUrl(
            'http://127.0.0.1:8188',
            processes: const [],
          ),
          isNull,
        );
      },
    );

    test('a ComfyUI on another computer is never patched', () async {
      final result = await gate().ensure(
        comfyUrl: 'http://203.0.113.9:8188',
        graph: _graph(),
      );
      expect(result.state, City96State.needsUpdate);
      expect(result.message, startsWith(kCity96NeedsUpdate));
      expect(result.message, contains('another computer'));
      expect(located, 0);
      expect(loader.readAsStringSync(), kStockCity96Loader);
    });
  });

  group(
    '(c) ask once, keep a .bak, write through a temp file, ask for a restart',
    () {
      test(
        'yes: the loader is updated, the original is kept, and a restart is asked for',
        () async {
          final result = await gate().ensure(
            comfyUrl: 'http://127.0.0.1:8188',
            graph: _graph(),
          );
          expect(asked, hasLength(1));
          expect(asked.single.loaderPath, loader.path);
          expect(result.state, City96State.restartNeeded);
          expect(result.message, contains('Restart ComfyUI'));
          expect(
            loader.readAsStringSync(),
            contains('arch_str = "qwen_image"'),
          );
          expect(loader.readAsStringSync(), contains('arch == "qwen3vl"'));
          expect(
            File('${loader.path}.bak').readAsStringSync(),
            kStockCity96Loader,
          );
          expect(File('${loader.path}.fpai-tmp').existsSync(), isFalse);
        },
      );

      test(
        'the update counts once ComfyUI has restarted, not when the file changes',
        () async {
          final g = gate();
          await g.ensure(comfyUrl: 'http://127.0.0.1:8188', graph: _graph());
          asked.clear();

          // The file is updated, but the ComfyUI that is running is the same
          // process and has not loaded it.
          final waiting = await g.ensure(
            comfyUrl: 'http://127.0.0.1:8188',
            graph: _graph(),
          );
          expect(waiting.state, City96State.restartNeeded);
          expect(waiting.message, contains('Restart ComfyUI'));
          expect(
            (await g.check(
              comfyUrl: 'http://127.0.0.1:8188',
              graph: _graph(),
            )).state,
            City96State.restartNeeded,
          );

          comfyPid = 200;
          final again = await g.ensure(
            comfyUrl: 'http://127.0.0.1:8188',
            graph: _graph(),
          );
          expect(again.state, City96State.ready);
          expect(asked, isEmpty);
        },
      );

      group(
        'whether ComfyUI has loaded the update follows the process, not memory',
        () {
          const url = 'http://127.0.0.1:8188';
          final patched = patchCity96Loader(kStockCity96Loader).source;

          City96Gate started(int? pid, DateTime? at) => City96Gate(
            locate: (_) async => loader,
            pidFor: (_) async => pid,
            probe: FakeProbe(starts: {?pid: ?at}),
          );

          test(
            'the same gate stops saying restart once ComfyUI restarted, even when the id was unknown at write',
            () async {
              int? pid;
              final restartedAt = DateTime.now().add(
                const Duration(minutes: 5),
              );
              final g = City96Gate(
                locate: (_) async => loader,
                ask: (_) async => true,
                pidFor: (_) async => pid,
                probe: FakeProbe(starts: {300: restartedAt}),
              );
              await g.ensure(comfyUrl: url, graph: _graph());
              expect(
                (await g.check(comfyUrl: url, graph: _graph())).state,
                City96State.restartNeeded,
                reason: 'nothing tells it ComfyUI restarted yet',
              );

              pid = 300;
              expect(
                (await g.check(comfyUrl: url, graph: _graph())).state,
                City96State.ready,
              );
              expect(
                (await g.check(comfyUrl: url, graph: _graph())).state,
                City96State.ready,
                reason: 'and it stays cleared',
              );
            },
          );

          test(
            'an app restart does not make an unloaded update look Ready',
            () async {
              loader.writeAsStringSync(patched);
              // ComfyUI started an hour before the loader was written.
              final g = started(
                100,
                DateTime.now().subtract(const Duration(hours: 1)),
              );
              final result = await g.check(comfyUrl: url, graph: _graph());
              expect(result.state, City96State.restartNeeded);
              expect(result.message, contains('Restart ComfyUI'));
            },
          );

          test('an update written before ComfyUI started is Ready', () async {
            loader.writeAsStringSync(patched);
            loader.setLastModifiedSync(
              DateTime.now().subtract(const Duration(hours: 2)),
            );
            final g = started(
              100,
              DateTime.now().subtract(const Duration(hours: 1)),
            );
            expect(
              (await g.check(comfyUrl: url, graph: _graph())).state,
              City96State.ready,
            );
          });

          test(
            'with no start time to read, an update this run made still waits',
            () async {
              final g = City96Gate(
                locate: (_) async => loader,
                ask: (_) async => true,
                pidFor: (_) async => 100,
              );
              await g.ensure(comfyUrl: url, graph: _graph());
              expect(
                (await g.check(comfyUrl: url, graph: _graph())).state,
                City96State.restartNeeded,
              );
            },
          );
        },
      );

      test(
        'no: nothing is written, and the question is not asked again',
        () async {
          answer = false;
          final g = gate();
          final first = await g.ensure(
            comfyUrl: 'http://127.0.0.1:8188',
            graph: _graph(),
          );
          final second = await g.ensure(
            comfyUrl: 'http://127.0.0.1:8188',
            graph: _graph(),
          );
          expect(asked, hasLength(1));
          for (final r in [first, second]) {
            expect(r.state, City96State.needsUpdate);
            expect(r.message, startsWith(kCity96NeedsUpdate));
            expect(r.message, contains('chose not to'));
          }
          expect(loader.readAsStringSync(), kStockCity96Loader);
          expect(File('${loader.path}.bak').existsSync(), isFalse);
        },
      );

      test(
        'with no desktop to ask (phone, tests) nothing is written',
        () async {
          final result = await gate(
            withAsker: false,
          ).ensure(comfyUrl: 'http://127.0.0.1:8188', graph: _graph());
          expect(result.state, City96State.needsUpdate);
          expect(result.message, contains('allow the update'));
          expect(loader.readAsStringSync(), kStockCity96Loader);
        },
      );

      test('check() reports without asking or writing', () async {
        final result = await gate().check(
          comfyUrl: 'http://127.0.0.1:8188',
          graph: _graph(),
        );
        expect(result.state, City96State.needsUpdate);
        expect(asked, isEmpty);
        expect(loader.readAsStringSync(), kStockCity96Loader);
      });

      test(
        'a write that fails is reported and leaves the loader as it was',
        () async {
          final result = await City96Gate(
            locate: (_) async => loader,
            ask: (_) async => true,
            pidFor: (_) async => 100,
            write: (_, _) async => throw const FileSystemException('disk full'),
          ).ensure(comfyUrl: 'http://127.0.0.1:8188', graph: _graph());
          expect(result.state, City96State.needsUpdate);
          expect(result.message, contains('could not be written'));
          expect(loader.readAsStringSync(), kStockCity96Loader);
        },
      );
    },
  );

  group(
    '(d) when it cannot patch, that model says why and nothing else stops',
    () {
      test('no install found at the URL (Docker, say)', () async {
        final result = await City96Gate(
          locate: (_) async => null,
          ask: (_) async => true,
        ).ensure(comfyUrl: 'http://127.0.0.1:8188', graph: _graph());
        expect(result.state, City96State.needsUpdate);
        expect(result.message, startsWith(kCity96NeedsUpdate));
        expect(result.message, contains('Docker'));
      });

      test('a loader version it does not recognize is left alone', () async {
        loader.writeAsStringSync('# a fork of ComfyUI-GGUF\n');
        final result = await gate().ensure(
          comfyUrl: 'http://127.0.0.1:8188',
          graph: _graph(),
        );
        expect(result.state, City96State.needsUpdate);
        expect(result.message, contains('does not recognize'));
        expect(asked, isEmpty);
        expect(loader.readAsStringSync(), '# a fork of ComfyUI-GGUF\n');
      });

      test('ensureOrThrow stops only a graph that needs it', () async {
        final g = City96Gate(locate: (_) async => null);
        await g.ensureOrThrow(
          comfyUrl: 'http://127.0.0.1:8188',
          graph: _graph(unet: 'flux1-dev-Q4_K.gguf', clip: 't5xxl.gguf'),
        );
        await expectLater(
          g.ensureOrThrow(comfyUrl: 'http://127.0.0.1:8188', graph: _graph()),
          throwsA(
            isA<ComfyLoaderUpdateNeeded>().having(
              (e) => e.message,
              'message',
              startsWith(kCity96NeedsUpdate),
            ),
          ),
        );
      });
    },
  );
}
