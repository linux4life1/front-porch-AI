// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:path/path.dart' as path;

/// One block from a Comfy extra-model-paths YAML.
class ComfyModelConfig {
  final String basePath;
  final bool isDefault;

  /// Folder key to the path lines Comfy searches, in order.
  final Map<String, List<String>> folders;

  const ComfyModelConfig({
    required this.basePath,
    required this.isDefault,
    required this.folders,
  });
}

/// Paths Comfy Desktop and a manual install use on one operating system.
class ComfyMachineLayout {
  final ComfyHostOs os;
  final String home;
  final List<String> desktopConfigDirs;
  final List<String> extraModelConfigFiles;
  final List<String> installSearchRoots;
  final List<String> webuiPackageRoots;

  const ComfyMachineLayout({
    required this.os,
    required this.home,
    required this.desktopConfigDirs,
    required this.extraModelConfigFiles,
    required this.installSearchRoots,
    required this.webuiPackageRoots,
  });
}

enum ComfyHostOs { mac, windows, linux }

/// A running Comfy or Automatic1111 process.
class ComfyProcessSnapshot {
  final String command;
  final String? cwd;
  final String? executable;

  const ComfyProcessSnapshot({
    required this.command,
    this.cwd,
    this.executable,
  });
}

/// Model locations named on a Comfy command line.
class ComfyLaunchHints {
  final int? port;
  final String? modelsDirectory;
  final String? baseDirectory;
  final String? mainPyDir;
  final List<String> extraYamls;

  const ComfyLaunchHints({
    required this.port,
    required this.modelsDirectory,
    required this.baseDirectory,
    required this.mainPyDir,
    required this.extraYamls,
  });
}

const _kSlotDirs = {
  'loras',
  'diffusion_models',
  'checkpoints',
  'vae',
  'text_encoders',
  'clip',
  'unet',
};

/// Blocks in a Comfy Desktop or `extra_model_paths.yaml` file.
List<ComfyModelConfig> parseComfyModelYaml(String yaml) {
  final blocks = <ComfyModelConfig>[];
  String? base;
  var isDefault = false;
  final folders = <String, List<String>>{};
  String? multiKey;
  var multiIndent = 0;
  var inBlock = false;

  void flush() {
    if (!inBlock) return;
    blocks.add(
      ComfyModelConfig(
        basePath: base ?? '',
        isDefault: isDefault,
        folders: {
          for (final entry in folders.entries)
            entry.key: List<String>.from(entry.value),
        },
      ),
    );
    base = null;
    isDefault = false;
    folders.clear();
    multiKey = null;
    inBlock = false;
  }

  for (final raw in yaml.split('\n')) {
    final line = raw.replaceAll('\r', '');
    if (multiKey != null) {
      if (line.trim().isEmpty) continue;
      if (_indent(line) > multiIndent) {
        folders.putIfAbsent(multiKey!, () => []).add(line.trim());
        continue;
      }
      multiKey = null;
    }
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
    final indent = _indent(line);
    if (indent == 0) {
      flush();
      inBlock = trimmed.endsWith(':');
      continue;
    }
    if (!inBlock) continue;
    final colon = trimmed.indexOf(':');
    if (colon <= 0) continue;
    final key = _unquote(trimmed.substring(0, colon).trim());
    final value = trimmed.substring(colon + 1).trim();
    if (value == '|' || value == '|-' || value == '>' || value == '>-') {
      multiKey = key;
      multiIndent = indent;
      continue;
    }
    if (key == 'base_path') {
      base = _unquote(value);
    } else if (key == 'is_default') {
      isDefault = _truthy(value);
    } else if (value.isNotEmpty) {
      folders.putIfAbsent(key, () => []).add(_unquote(value));
    }
  }
  flush();
  return blocks;
}

/// Directory that already contains `loras`, `diffusion_models`, and the
/// other Comfy slot folders. `base_path` itself is that directory only when
/// the YAML's folder lines are single names (`loras/`). An install-shaped
/// file (`loras: models/loras/`) keeps the models folder one level down.
String? comfyModelsRoot({
  required ComfyModelConfig config,
  required String yamlDir,
  required String home,
}) {
  final base = _resolve(config.basePath, '', yamlDir, home);
  String? loraParent;
  String? anyParent;
  for (final entry in config.folders.entries) {
    if (entry.value.isEmpty) continue;
    final abs = _resolve(entry.value.first, base, yamlDir, home);
    final ctx = _ctxFor(abs);
    final name = ctx.basename(abs).toLowerCase();
    if (!_kSlotDirs.contains(name)) continue;
    final parent = ctx.dirname(abs);
    anyParent ??= parent;
    if (entry.key == 'loras') loraParent = parent;
  }
  if (loraParent != null && loraParent.isNotEmpty) return loraParent;
  if (anyParent != null && anyParent.isNotEmpty) return anyParent;
  if (base.isEmpty) return null;
  return base;
}

/// `--models-directory`, `--base-directory`, and extra YAML paths.
ComfyLaunchHints comfyLaunchHints(
  String command, {
  String? cwd,
  String? executable,
}) {
  final work = (cwd == null || cwd.isEmpty)
      ? _cwdFromExecutable(executable)
      : cwd;
  final args = splitCommandLine(command);
  final portText = _opt(args, '--port');
  final port = portText == null ? _defaultPort(args) : int.tryParse(portText);
  final mainArg = args.cast<String?>().firstWhere(
    (arg) => arg != null && arg.toLowerCase().endsWith('main.py'),
    orElse: () => null,
  );
  final mainAbs = _abs(mainArg, work);
  return ComfyLaunchHints(
    port: port,
    modelsDirectory: _abs(_opt(args, '--models-directory'), work),
    baseDirectory: _abs(_opt(args, '--base-directory'), work),
    mainPyDir: mainAbs == null ? null : _ctxFor(mainAbs).dirname(mainAbs),
    extraYamls: [
      for (final yaml in _multi(args, '--extra-model-paths-config'))
        ?_abs(yaml, work),
    ],
  );
}

/// Splits a process command on whitespace, keeping quoted paths intact.
List<String> splitCommandLine(String command) {
  final out = <String>[];
  final buf = StringBuffer();
  String? quote;
  for (final char in command.split('')) {
    if (quote != null) {
      if (char == quote) {
        quote = null;
      } else {
        buf.write(char);
      }
      continue;
    }
    if (char == '"' || char == "'") {
      quote = char;
      continue;
    }
    if (char == ' ' || char == '\t') {
      if (buf.isNotEmpty) {
        out.add(buf.toString());
        buf.clear();
      }
      continue;
    }
    buf.write(char);
  }
  if (buf.isNotEmpty) out.add(buf.toString());
  return out;
}

/// Comfy Desktop's model YAML, manual install roots, and webui package roots.
ComfyMachineLayout comfyMachineLayout({
  required ComfyHostOs os,
  required String home,
  String? appData,
  String? localAppData,
  String? xdgDataHome,
  String? xdgConfigHome,
}) {
  final ctx = os == ComfyHostOs.windows
      ? path.Context(style: path.Style.windows)
      : path.Context(style: path.Style.posix);
  final roaming =
      appData ??
      (os == ComfyHostOs.windows ? ctx.join(home, 'AppData', 'Roaming') : '');
  final local =
      localAppData ??
      (os == ComfyHostOs.windows ? ctx.join(home, 'AppData', 'Local') : '');
  final xdgData = (xdgDataHome == null || xdgDataHome.isEmpty)
      ? ctx.join(home, '.local', 'share')
      : xdgDataHome;
  final xdgConfig = (xdgConfigHome == null || xdgConfigHome.isEmpty)
      ? ctx.join(home, '.config')
      : xdgConfigHome;
  final desktop = <String>[];
  final extras = <String>[];
  final installs = <String>[
    ctx.join(home, 'ComfyUI-Installs'),
    ctx.join(home, 'ComfyUI'),
    ctx.join(home, 'Documents', 'ComfyUI'),
  ];
  final packages = <String>[];
  switch (os) {
    case ComfyHostOs.mac:
      desktop.add(
        ctx.join(
          home,
          'Library',
          'Application Support',
          'Comfy Desktop',
          'instance-model-paths',
        ),
      );
      extras.add(
        ctx.join(
          home,
          'Library',
          'Application Support',
          'ComfyUI',
          'extra_models_config.yaml',
        ),
      );
      packages.add(
        ctx.join(
          home,
          'Library',
          'Application Support',
          'StabilityMatrix',
          'Packages',
        ),
      );
    case ComfyHostOs.windows:
      desktop.add(ctx.join(roaming, 'Comfy Desktop', 'instance-model-paths'));
      extras.add(ctx.join(roaming, 'ComfyUI', 'extra_models_config.yaml'));
      installs.add(ctx.join(local, 'Comfy-Desktop', 'ComfyUI-Installs'));
      installs.add(ctx.join(home, 'ComfyUI_windows_portable'));
      packages.add(ctx.join(roaming, 'StabilityMatrix', 'Packages'));
    case ComfyHostOs.linux:
      desktop.add(
        ctx.join(xdgData, 'comfyui-desktop-2', 'instance-model-paths'),
      );
      desktop.add(
        ctx.join(xdgConfig, 'comfyui-desktop-2', 'instance-model-paths'),
      );
      packages.add(ctx.join(xdgData, 'StabilityMatrix', 'Packages'));
      packages.add(ctx.join(xdgConfig, 'StabilityMatrix', 'Packages'));
  }
  return ComfyMachineLayout(
    os: os,
    home: home,
    desktopConfigDirs: desktop,
    extraModelConfigFiles: extras,
    installSearchRoots: installs,
    webuiPackageRoots: packages,
  );
}

/// Port on a Comfy URL. A URL without a port is Comfy's own default, 8188.
int comfyUrlPort(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null || !uri.hasPort) return 8188;
  return uri.port;
}

int _indent(String line) {
  var count = 0;
  for (final char in line.split('')) {
    if (char != ' ' && char != '\t') break;
    count++;
  }
  return count;
}

String _unquote(String raw) {
  var value = raw.trim();
  if (value.length >= 2) {
    final quote = value[0];
    if ((quote == "'" || quote == '"') && value.endsWith(quote)) {
      value = value.substring(1, value.length - 1);
    }
  }
  return value;
}

bool _truthy(String raw) {
  switch (_unquote(raw).trim().toLowerCase()) {
    case 'true':
    case 'yes':
    case '1':
      return true;
    default:
      return false;
  }
}

path.Context _ctxFor(String value) {
  if (value.contains('\\') || RegExp(r'^[A-Za-z]:').hasMatch(value)) {
    return path.Context(style: path.Style.windows);
  }
  return path.Context(style: path.Style.posix);
}

bool _isAbs(String value, path.Context ctx) {
  if (ctx.style == path.Style.windows &&
      RegExp(r'^[A-Za-z]:[\\/]').hasMatch(value)) {
    return true;
  }
  return ctx.isAbsolute(value);
}

String _expandHome(String value, String home) {
  if (home.isEmpty) return value;
  if (value == '~') return home;
  if (value.startsWith('~/') || value.startsWith('~\\')) {
    return '$home${value.substring(1)}';
  }
  return value;
}

String _resolve(String value, String base, String yamlDir, String home) {
  final expanded = _expandHome(value.trim(), home);
  if (expanded.isEmpty) return '';
  final ctx = _ctxFor('$base $yamlDir $expanded');
  if (_isAbs(expanded, ctx)) return ctx.normalize(expanded);
  final root = base.isNotEmpty
      ? (_isAbs(base, ctx) ? base : ctx.join(yamlDir, base))
      : yamlDir;
  if (root.isEmpty) return ctx.normalize(expanded);
  return ctx.normalize(ctx.join(root, expanded));
}

String? _abs(String? value, String? cwd) {
  if (value == null || value.trim().isEmpty) return null;
  final expanded = value.trim();
  final ctx = _ctxFor('${cwd ?? ''} $expanded');
  if (_isAbs(expanded, ctx)) return ctx.normalize(expanded);
  if (cwd == null || cwd.isEmpty) return expanded;
  return ctx.normalize(ctx.join(cwd, expanded));
}

String? _cwdFromExecutable(String? executable) {
  if (executable == null || executable.isEmpty) return null;
  final ctx = _ctxFor(executable);
  final dir = ctx.dirname(executable);
  switch (ctx.basename(dir).toLowerCase()) {
    case 'python_embeded':
    case 'python_embedded':
    case 'bin':
    case 'scripts':
      return ctx.dirname(dir);
    default:
      return dir;
  }
}

int? _defaultPort(List<String> args) {
  for (final arg in args) {
    if (arg.toLowerCase().endsWith('main.py')) return 8188;
  }
  return null;
}

String? _opt(List<String> args, String name) {
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg == name && i + 1 < args.length) return args[i + 1];
    final prefix = '$name=';
    if (arg.startsWith(prefix)) return arg.substring(prefix.length);
  }
  return null;
}

List<String> _multi(List<String> args, String name) {
  final out = <String>[];
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg == name) {
      var next = i + 1;
      while (next < args.length && !args[next].startsWith('--')) {
        out.add(args[next]);
        next++;
      }
    } else {
      final prefix = '$name=';
      if (arg.startsWith(prefix)) out.add(arg.substring(prefix.length));
    }
  }
  return out;
}
