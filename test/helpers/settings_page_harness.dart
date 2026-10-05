// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The real SettingsPage, mounted with the golden fakes for the services it
// only reads. What runs for real: KoboldService.launch, resolveKoboldLaunch,
// recordKoboldModelInUse, koboldLaunchProblem, the model file check and the
// Local model card, on model files grown to full size from real GGUF header
// fixtures. What is replaced is only what would leave the process: the
// engine start (recorded, no process), the live reload (counted) and the OS
// file picker (the app's own PickerPrefs seam).

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/web/web_server_host.dart';
import 'package:front_porch_ai/ui/pages/pages.dart';
import 'package:front_porch_ai/utils/utils.dart';

import '../golden/support/fakes.dart';
import '../golden/support/fakes_services.dart';
import '../golden/support/fakes_storage.dart';

class SettingsPageStorage extends FakeStorageService {
  SettingsPageStorage(this.bin) {
    unawaited(backendSettings.setBackendType('kobold'));
  }

  final Directory bin;

  @override
  Directory get binDir => bin;

  @override
  String get spellCheckLanguage => 'off';
}

/// The machine the page sees when a test does not say otherwise.
final nvidiaGtx1060 = HardwareInfo(
  gpuName: 'NVIDIA GeForce GTX 1060 6GB',
  vramMb: 6144,
  ramMb: 16384,
  vendor: 'Nvidia',
  hasCuda: true,
);

/// A machine with the memory readings the Local model card waits for.
class SettingsPageHardware extends FakeHardwareService {
  SettingsPageHardware(HardwareInfo info) : super(hardwareInfo: info);

  FreeMemoryMb? _free = (graphics: 5222, system: 11063);

  @override
  FreeMemoryMb? get freeBeforeEngine => _free;

  @override
  set freeBeforeEngine(FreeMemoryMb? value) => _free = value;
}

/// What the engine was asked to start with.
typedef RecordedStart = ({
  String model,
  String? kcpps,
  int context,
  int layers,
  bool cublas,
  bool vulkan,
  bool metal,
  bool rocm,
});

/// The real KoboldService; only the process spawn is replaced.
class RecordingKobold extends KoboldService {
  RecordingKobold(super.storage);

  final starts = <RecordedStart>[];

  @override
  Future<void> reconnectIfAlive() async {}

  @override
  Future<KoboldLaunchResult> startKobold(
    String executablePath,
    String modelPath, {
    String? kcppsPath,
    String? mmprojPath,
    int port = 5001,
    int gpuLayers = 0,
    int contextSize = 4096,
    bool useVulkan = false,
    bool useCublas = false,
    bool useMetal = false,
    bool useRocm = false,
  }) async {
    starts.add((
      model: modelPath,
      kcpps: kcppsPath,
      context: contextSize,
      layers: gpuLayers,
      cublas: useCublas,
      vulkan: useVulkan,
      metal: useMetal,
      rocm: useRocm,
    ));
    return const KoboldLaunchResult.started();
  }
}

/// Counts the live reloads of a running KoboldCpp instead of running them.
class ReloadCountingLlm extends FakeLLMProvider {
  ReloadCountingLlm(this.kobold);

  final KoboldService kobold;
  int reloads = 0;

  @override
  KoboldService get koboldService => kobold;

  @override
  Future<void> reloadChatKobold() async => reloads++;
}

class ReadyBackendManager extends ChangeNotifier implements BackendManager {
  ReadyBackendManager(this.exe);

  final String exe;

  @override
  String? get backendPath => exe;
  @override
  bool get isIntelMac => false;
  @override
  String? get error => null;
  @override
  bool get isDownloading => false;
  @override
  bool get isCheckingVersion => false;
  @override
  double get downloadProgress => 0;
  @override
  String? get versionError => null;
  @override
  String? get remoteVersion => '1.122.1';
  @override
  bool get isUpdateAvailable => false;
  @override
  String get localVersionDisplay => 'v1.122.1';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class ListedModels extends FakeModelManager {
  ListedModels(this.paths);

  final List<String> paths;

  @override
  List<FileSystemEntity> get models => [for (final f in paths) File(f)];

  @override
  Future<GGUFModelInfo?> getModelArchitectureInfo(String filePath) async =>
      null;

  @override
  GGUFModelInfo? getCachedModelArchitectureInfo(String filePath) => null;
}

class IdleClassifier extends ChangeNotifier
    implements ExpressionClassifierService {
  @override
  bool get modelReady => false;
  @override
  bool get isModelCached => false;
  @override
  bool get isDownloading => false;
  @override
  OnnxDownloadProgress? get downloadProgress => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class IdleWebServer extends ChangeNotifier implements WebServerHost {
  @override
  bool get isRunning => false;
  @override
  String? get lastStartError => null;
  @override
  bool get lastStartPortConflict => false;
  @override
  bool get hasActiveClient => false;
  @override
  String? get connectedClientIp => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A file on disk as the OS picker hands it back.
base class PickedFile extends PlatformFile {
  PickedFile(this.filePath);

  final String filePath;

  @override
  String get name => p.basename(filePath);
  @override
  Uri get uri => Uri.file(filePath);
  @override
  XFile get xFile => XFile(filePath);
  @override
  int? lengthSync() => File(filePath).lengthSync();
  @override
  Future<int?> length() => File(filePath).length();
  @override
  Future<Uint8List> readAsBytes() => File(filePath).readAsBytes();
  @override
  Stream<Uint8List> readAsByteStream() =>
      File(filePath).openRead().map(Uint8List.fromList);
}

class SettingsPageRig {
  SettingsPageRig({
    required this.dir,
    required this.store,
    required this.kobold,
    required this.llm,
    required this.a,
    required this.b,
  });

  final Directory dir;
  final SettingsPageStorage store;
  final RecordingKobold kobold;
  final ReloadCountingLlm llm;

  /// The first model in the models folder, and the second one.
  final String a;
  final String b;

  late final ListedModels models;
  late final ReadyBackendManager backend;
}

/// A model file grown to its real size from a real GGUF header fixture.
Future<String> writeGgufModel(
  Directory dir,
  String fixture,
  String name,
) async {
  final fx = 'test/fixtures/gguf_headers/$fixture';
  final side = jsonDecode(File('$fx.json').readAsStringSync()) as Map;
  final model = p.join(dir.path, name);
  final raf = await File(model).open(mode: FileMode.write);
  await raf.writeFrom(File('$fx.gguf').readAsBytesSync());
  await raf.setPosition((side['fixture_file_bytes'] as int) - 1);
  await raf.writeByte(0);
  await raf.close();
  return model;
}

/// Lets the page's real file and storage work finish, which the test clock
/// does not drive. Stops as soon as [done] says so, or after a few frames.
Future<void> settle(WidgetTester tester, [bool Function()? done]) async {
  for (var i = 0; i < 300; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 10));
    if (done == null ? i >= 8 : done()) return;
  }
  fail('still not done after 6 seconds');
}

/// Mounts the real Settings page over two models in one folder, [SettingsPageRig.a]
/// first and [SettingsPageRig.b] second. [lastUsedIsB] picks the last-used
/// one. [before] runs once the files exist, ahead of the first frame.
Future<SettingsPageRig> mountSettings(
  WidgetTester tester, {
  required bool lastUsedIsB,
  int context = 16384,
  HardwareInfo? hardware,
  Future<void> Function(SettingsPageRig rig)? before,
}) async {
  await tester.binding.setSurfaceSize(const Size(1400, 2600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  SharedPreferences.setMockInitialValues({});
  late SettingsPageRig rig;
  await tester.runAsync(() async {
    final dir = await Directory.systemTemp.createTemp('fpai settings page');
    final bin = await Directory(p.join(dir.path, 'bin')).create();
    final exe = p.join(bin.path, 'koboldcpp');
    File(exe).writeAsStringSync('#!/bin/sh\n');
    final a = await writeGgufModel(
      dir,
      'Qwen3.6-35B-A3B-Q4_K_XL',
      'a-Qwen3.6-35B-A3B-UD-Q4_K_XL.gguf',
    );
    final b = await writeGgufModel(dir, 'Llama-3.1-8B', 'b-Llama-3.1-8B.gguf');
    final store = SettingsPageStorage(bin);
    await store.backendSettings.setBackendType('kobold');
    await store.backendSettings.setLastUsedModelPath(lastUsedIsB ? b : a);
    await store.backendSettings.setContextSize(context);
    final kobold = RecordingKobold(store);
    rig = SettingsPageRig(
      dir: dir,
      store: store,
      kobold: kobold,
      llm: ReloadCountingLlm(kobold),
      a: a,
      b: b,
    );
    rig.models = ListedModels([a, b]);
    rig.backend = ReadyBackendManager(exe);
    await before?.call(rig);
  });
  addTearDown(() {
    rig.kobold.dispose();
    rig.dir.deleteSync(recursive: true);
  });

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<StorageService>.value(value: rig.store),
        ChangeNotifierProvider<KoboldService>.value(value: rig.kobold),
        ChangeNotifierProvider<LLMProvider>.value(value: rig.llm),
        ChangeNotifierProvider<HardwareService>.value(
          value: SettingsPageHardware(hardware ?? nvidiaGtx1060),
        ),
        ChangeNotifierProvider<ModelManager>.value(value: rig.models),
        ChangeNotifierProvider<BackendManager>.value(value: rig.backend),
        ChangeNotifierProvider<OpenRouterService>.value(
          value: OpenRouterService(),
        ),
        ChangeNotifierProvider(
          create: (_) =>
              OpenCodeManager(rootPath: '', remoteLookup: () async => null),
        ),
        ChangeNotifierProvider<UpdateService>.value(value: FakeUpdateService()),
        ChangeNotifierProvider<ExpressionClassifierService>.value(
          value: IdleClassifier(),
        ),
        ChangeNotifierProvider<WebServerHost>.value(value: IdleWebServer()),
      ],
      child: const MaterialApp(home: SettingsPage()),
    ),
  );
  await settle(tester);
  return rig;
}

Future<void> openTab(WidgetTester tester, String name) async {
  await tester.tap(find.widgetWithText(Tab, name));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
  await settle(tester);
}

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await tester.pump();
}

/// Opens [dropdown] and picks the entry labelled [item].
Future<void> pickFromDropdown(
  WidgetTester tester,
  Finder dropdown,
  String item,
) async {
  await tapVisible(tester, dropdown);
  await tester.pump(const Duration(milliseconds: 400));
  await tester.tap(find.text(item).last);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await settle(tester);
}
