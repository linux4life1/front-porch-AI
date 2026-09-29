// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'comfy_model_paths.dart';
import 'comfy_type_folders.dart';

const _kWeightExts = {'.safetensors', '.gguf', '.ckpt', '.pt', '.pth', '.bin'};

const _kWebuiNames = [
  'stable-diffusion-webui',
  'stable-diffusion-webui-forge',
  'stable-diffusion-webui-directml',
  'stable-diffusion-webui-reForge',
  'forge',
];

/// Layout of the computer this process is running on.
ComfyMachineLayout currentComfyMachineLayout() {
  final os = Platform.isWindows
      ? ComfyHostOs.windows
      : Platform.isLinux
      ? ComfyHostOs.linux
      : ComfyHostOs.mac;
  final env = Platform.environment;
  return comfyMachineLayout(
    os: os,
    home: env['HOME'] ?? env['USERPROFILE'] ?? '',
    appData: env['APPDATA'],
    localAppData: env['LOCALAPPDATA'],
    xdgDataHome: env['XDG_DATA_HOME'],
    xdgConfigHome: env['XDG_CONFIG_HOME'],
  );
}

/// True when [url] names this computer. A remote Comfy cannot receive a
/// download written on the machine running Front Porch.
Future<bool> comfyHostIsLocal(String url) async {
  final uri = Uri.tryParse(url.trim());
  final host = uri?.host.toLowerCase() ?? '';
  if (host.isEmpty ||
      host == 'localhost' ||
      host == '127.0.0.1' ||
      host == '::1' ||
      host == '0.0.0.0') {
    return true;
  }
  try {
    final faces = await NetworkInterface.list(
      includeLinkLocal: true,
      type: InternetAddressType.any,
    );
    for (final face in faces) {
      for (final addr in face.addresses) {
        if (addr.address.toLowerCase() == host) return true;
      }
    }
  } on SocketException {
    return false;
  }
  return false;
}

/// Comfy's models folder, from the running server, Comfy Desktop, or an
/// install. The same folder is the parent of `loras` and `diffusion_models`.
Future<String?> discoverComfyModelsRoot({
  int? preferPort,
  ComfyMachineLayout? layout,
  List<ComfyProcessSnapshot>? processes,
  bool scanMachine = true,
}) async {
  final machine = layout ?? currentComfyMachineLayout();
  final procs =
      processes ??
      (scanMachine
          ? await scanComfyProcesses()
          : const <ComfyProcessSnapshot>[]);
  final candidates = <String>[];
  for (final proc in procs) {
    final hints = comfyLaunchHints(
      proc.command,
      cwd: proc.cwd,
      executable: proc.executable,
    );
    if (preferPort != null && hints.port != preferPort) continue;
    final yamls = [
      ...hints.extraYamls,
      if (hints.mainPyDir != null)
        p.join(hints.mainPyDir!, 'extra_model_paths.yaml'),
      if (proc.cwd != null) p.join(proc.cwd!, 'extra_model_paths.yaml'),
    ];
    candidates.addAll(await _rootsFromYamlFiles(yamls, machine.home));
    if (hints.modelsDirectory != null) candidates.add(hints.modelsDirectory!);
    candidates.addAll(_processCandidates(proc, hints));
  }
  candidates.addAll(await _yamlCandidates(machine));
  candidates.addAll(await _installCandidates(machine));
  return _pickModelsRoot(candidates);
}

/// Automatic1111's install root. Slot folders are `models/Lora` and
/// `models/Stable-diffusion` under the returned directory.
Future<String?> discoverAutomatic1111Root({
  String? home,
  List<String>? packageRoots,
  List<ComfyProcessSnapshot>? processes,
  bool scanMachine = true,
}) async {
  final procs =
      processes ??
      (scanMachine
          ? await scanComfyProcesses()
          : const <ComfyProcessSnapshot>[]);
  for (final proc in procs) {
    if (!_isWebuiCommand(proc.command)) continue;
    final cwd = proc.cwd;
    if (cwd != null && await _isWebuiRoot(cwd)) return cwd;
  }
  final roots = <String>[];
  final base = home ?? currentComfyMachineLayout().home;
  if (base.isNotEmpty) {
    for (final name in _kWebuiNames) {
      roots.add(p.join(base, name));
      roots.add(p.join(base, 'Documents', name));
    }
  }
  final packages =
      packageRoots ??
      (home == null
          ? currentComfyMachineLayout().webuiPackageRoots
          : const <String>[]);
  for (final package in packages) {
    roots.addAll(await _webuiPackages(package));
  }
  for (final root in roots) {
    if (await _isWebuiRoot(root)) return root;
  }
  return null;
}

/// Local `python main.py` / webui processes. Empty when the OS refuses.
Future<List<ComfyProcessSnapshot>> scanComfyProcesses() async {
  try {
    if (Platform.isWindows) return await _scanWindows();
    return await _scanPosix();
  } on ProcessException {
    return const [];
  } on FileSystemException {
    return const [];
  }
}

List<String> _processCandidates(
  ComfyProcessSnapshot proc,
  ComfyLaunchHints hints,
) {
  return [
    if (hints.modelsDirectory != null) hints.modelsDirectory!,
    if (hints.baseDirectory != null) p.join(hints.baseDirectory!, 'models'),
    if (hints.mainPyDir != null) p.join(hints.mainPyDir!, 'models'),
    if (proc.cwd != null) p.join(proc.cwd!, 'models'),
  ];
}

Future<List<String>> _rootsFromYamlFiles(
  List<String> paths,
  String home,
) async {
  final preferred = <String>[];
  final other = <String>[];
  for (final path in paths) {
    final file = File(path);
    if (!await file.exists()) continue;
    List<ComfyModelConfig> blocks;
    try {
      blocks = parseComfyModelYaml(await file.readAsString());
    } on FileSystemException {
      continue;
    }
    final yamlDir = p.dirname(file.path);
    for (final block in blocks) {
      final root = comfyModelsRoot(config: block, yamlDir: yamlDir, home: home);
      if (root == null || root.isEmpty) continue;
      (block.isDefault ? preferred : other).add(root);
    }
  }
  return [...preferred, ...other];
}

Future<List<String>> _machineYamlFiles(ComfyMachineLayout machine) async {
  final files = <String>[];
  for (final dirPath in machine.desktopConfigDirs) {
    final dir = Directory(dirPath);
    if (!await dir.exists()) continue;
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final lower = entity.path.toLowerCase();
      if (lower.endsWith('.yaml') || lower.endsWith('.yml')) {
        files.add(entity.path);
      }
    }
  }
  files.addAll(machine.extraModelConfigFiles);
  for (final install in await _installDirs(machine.installSearchRoots)) {
    files.add(p.join(install, 'extra_model_paths.yaml'));
  }
  return files;
}

Future<List<String>> _yamlCandidates(ComfyMachineLayout machine) async {
  return _rootsFromYamlFiles(await _machineYamlFiles(machine), machine.home);
}

/// The per-kind folders the YAML gives [modelsRoot]'s ComfyUI, keyed by slot
/// folder (`checkpoints`, `loras`...). Only blocks whose models folder is
/// [modelsRoot] count, and the first block to name a kind wins. Empty when
/// every kind lives under [modelsRoot] itself.
Future<Map<String, String>> discoverComfyTypeFolders(
  String modelsRoot, {
  int? preferPort,
  ComfyMachineLayout? layout,
  List<ComfyProcessSnapshot>? processes,
  bool scanMachine = true,
}) async {
  final machine = layout ?? currentComfyMachineLayout();
  final procs =
      processes ??
      (scanMachine
          ? await scanComfyProcesses()
          : const <ComfyProcessSnapshot>[]);
  final yamls = <String>[];
  for (final proc in procs) {
    final hints = comfyLaunchHints(
      proc.command,
      cwd: proc.cwd,
      executable: proc.executable,
    );
    if (preferPort != null && hints.port != preferPort) continue;
    yamls.addAll(hints.extraYamls);
    if (hints.mainPyDir != null) {
      yamls.add(p.join(hints.mainPyDir!, 'extra_model_paths.yaml'));
    }
    if (proc.cwd != null) {
      yamls.add(p.join(proc.cwd!, 'extra_model_paths.yaml'));
    }
  }
  yamls.addAll(await _machineYamlFiles(machine));
  final want = p.normalize(modelsRoot);
  final out = <String, String>{};
  final seen = <String>{};
  for (final path in yamls) {
    if (!seen.add(path)) continue;
    final file = File(path);
    if (!await file.exists()) continue;
    List<ComfyModelConfig> blocks;
    try {
      blocks = parseComfyModelYaml(await file.readAsString());
    } on FileSystemException {
      continue;
    }
    final yamlDir = p.dirname(file.path);
    for (final block in blocks) {
      final root = comfyModelsRoot(
        config: block,
        yamlDir: yamlDir,
        home: machine.home,
      );
      if (root == null || p.normalize(root) != want) continue;
      final folders = comfyTypeFolders(
        config: block,
        yamlDir: yamlDir,
        home: machine.home,
      );
      for (final entry in folders.entries) {
        out.putIfAbsent(entry.key, () => entry.value);
      }
    }
  }
  return out;
}

Future<List<String>> _installCandidates(ComfyMachineLayout machine) async {
  final out = <String>[];
  for (final install in await _installDirs(machine.installSearchRoots)) {
    out.add(p.join(install, 'models'));
  }
  return out;
}

Future<String?> _pickModelsRoot(List<String> candidates) async {
  final seen = <String>{};
  final existing = <String>[];
  for (final raw in candidates) {
    if (raw.isEmpty || !seen.add(raw)) continue;
    if (!await Directory(raw).exists()) continue;
    if (await _hasWeights(raw)) return raw;
    existing.add(raw);
  }
  if (existing.isEmpty) return null;
  return existing.first;
}

Future<bool> _hasWeights(String root) async {
  for (final folder in [
    'diffusion_models',
    'checkpoints',
    'loras',
    'text_encoders',
    'vae',
    'Lora',
    'Stable-diffusion',
  ]) {
    final dir = Directory(p.join(root, folder));
    if (!await dir.exists()) continue;
    try {
      await for (final entity in dir.list(followLinks: true)) {
        if (entity is! File) continue;
        final name = p.basename(entity.path).toLowerCase();
        if (name.startsWith('put_') || name == '.gitkeep') continue;
        if (_kWeightExts.contains(p.extension(name))) return true;
      }
    } on FileSystemException {
      continue;
    }
  }
  return false;
}

Future<bool> _isWebuiRoot(String root) async {
  return await Directory(p.join(root, 'models', 'Stable-diffusion')).exists() ||
      await Directory(p.join(root, 'models', 'Lora')).exists();
}

bool _isWebuiCommand(String command) {
  final lower = command.toLowerCase();
  return lower.contains('webui.py') || lower.contains('launch.py');
}

Future<List<String>> _webuiPackages(String packages) async {
  final dir = Directory(packages);
  if (!await dir.exists()) return const [];
  final found = <String>[];
  try {
    await for (final entity in dir.list()) {
      if (entity is! Directory) continue;
      if (await _isWebuiRoot(entity.path)) found.add(entity.path);
      await for (final child in entity.list()) {
        if (child is Directory && await _isWebuiRoot(child.path)) {
          found.add(child.path);
        }
      }
    }
  } on FileSystemException {
    return found;
  }
  return found;
}

Future<List<String>> _installDirs(List<String> roots) async {
  final found = <String>[];
  for (final root in roots) {
    await _walkInstall(Directory(root), 0, found);
  }
  return found;
}

Future<void> _walkInstall(Directory dir, int depth, List<String> found) async {
  if (depth > 3 || !await dir.exists()) return;
  if (await File(p.join(dir.path, 'main.py')).exists()) {
    found.add(dir.path);
    return;
  }
  if (depth == 3) return;
  try {
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! Directory) continue;
      final name = p.basename(entity.path);
      if (name.startsWith('.') || name == 'models' || name == 'custom_nodes') {
        continue;
      }
      await _walkInstall(entity, depth + 1, found);
    }
  } on FileSystemException {
    return;
  }
}

Future<List<ComfyProcessSnapshot>> _scanPosix() async {
  final result = await Process.run('ps', ['-axww', '-o', 'pid=,args=']);
  if (result.exitCode != 0) return const [];
  final snaps = <ComfyProcessSnapshot>[];
  for (final raw in '${result.stdout}'.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    final split = line.indexOf(' ');
    if (split <= 0) continue;
    final pid = int.tryParse(line.substring(0, split));
    final command = line.substring(split + 1).trim();
    if (pid == null || !_interestingCommand(command)) continue;
    snaps.add(
      ComfyProcessSnapshot(command: command, cwd: await _posixCwd(pid)),
    );
  }
  return snaps;
}

Future<String?> _posixCwd(int pid) async {
  if (Platform.isLinux) {
    try {
      return await Directory('/proc/$pid/cwd').resolveSymbolicLinks();
    } on FileSystemException {
      return null;
    }
  }
  final result = await Process.run('lsof', [
    '-a',
    '-p',
    '$pid',
    '-d',
    'cwd',
    '-Fn',
  ]);
  if (result.exitCode != 0) return null;
  for (final raw in '${result.stdout}'.split('\n')) {
    if (raw.startsWith('n') && raw.length > 1) return raw.substring(1);
  }
  return null;
}

Future<List<ComfyProcessSnapshot>> _scanWindows() async {
  final result = await Process.run('powershell', [
    '-NoProfile',
    '-Command',
    r"Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -and ($_.CommandLine -match 'main.py' -or $_.CommandLine -match 'webui.py' -or $_.CommandLine -match 'launch.py') } | Select-Object ProcessId, CommandLine, ExecutablePath | ConvertTo-Json -Compress",
  ]);
  if (result.exitCode != 0) return const [];
  final text = '${result.stdout}'.trim();
  if (text.isEmpty) return const [];
  final decoded = jsonDecode(text);
  final rows = decoded is List ? decoded : [decoded];
  final snaps = <ComfyProcessSnapshot>[];
  for (final row in rows) {
    if (row is! Map) continue;
    final command = row['CommandLine']?.toString() ?? '';
    if (!_interestingCommand(command) && !_isWebuiCommand(command)) continue;
    snaps.add(
      ComfyProcessSnapshot(
        command: command,
        executable: row['ExecutablePath']?.toString(),
      ),
    );
  }
  return snaps;
}

bool _interestingCommand(String command) {
  final lower = command.toLowerCase();
  if (lower.contains('webui.py') || lower.contains('launch.py')) return true;
  if (!lower.contains('main.py')) return false;
  return lower.contains('--port') ||
      lower.contains('--listen') ||
      lower.contains('comfy');
}
