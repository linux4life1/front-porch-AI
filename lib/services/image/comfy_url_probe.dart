// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/services/comfy_ui_service.dart';
import 'package:front_porch_ai/services/storage/settings/image_gen_settings.dart';

import 'comfy_model_paths.dart';
import 'local_model_roots.dart';

/// Ports tried last, after the saved address, the running servers and
/// ComfyUI Desktop's setting: ComfyUI's default, Desktop's default, and the
/// next one up.
const List<int> kComfyFallbackPorts = [8188, 8000, 8189];

/// How long one candidate has to answer.
const Duration kComfyProbeTimeout = Duration(milliseconds: 1500);

/// [input] as a ComfyUI address: a scheme is added when there is none, and
/// it must be a host with an optional port of 1 to 65535 and no path. Null
/// when it is not one.
String? normalizeComfyAddress(String input) {
  final withScheme = ComfyUiService.ensureHttpScheme(input);
  if (withScheme.isEmpty) return null;
  final uri = Uri.tryParse(withScheme);
  if (uri == null ||
      (uri.scheme != 'http' && uri.scheme != 'https') ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      (uri.path.isNotEmpty && uri.path != '/')) {
    return null;
  }
  // Uri accepts any number after the colon; a port must fit in 16 bits.
  final written = RegExp(r':(\d+)$').firstMatch(withScheme.split('/')[2]);
  if (written != null) {
    final port = int.parse(written.group(1)!);
    if (port < 1 || port > 65535) return null;
  }
  return withScheme;
}

/// True when a ComfyUI answers at [url]: `GET /system_stats` replies with
/// `system.comfyui_version`. Anything else on the port (another app that
/// also says 200) is not one.
Future<bool> comfyAnswersAt(
  String url, {
  Duration timeout = kComfyProbeTimeout,
}) async {
  final client = http.Client();
  try {
    final root = ComfyUiService.ensureHttpScheme(url);
    final r = await client
        .get(Uri.parse('$root/system_stats'))
        .timeout(timeout);
    if (r.statusCode != 200) return false;
    final body = jsonDecode(r.body);
    if (body is! Map) return false;
    final system = body['system'];
    return system is Map && system['comfyui_version'] is String;
  } catch (_) {
    return false;
  } finally {
    client.close();
  }
}

/// ComfyUI Desktop's `config.json`, in the app's own data folder.
String? comfyDesktopConfigPath() {
  final env = Platform.environment;
  final home = env['HOME'] ?? env['USERPROFILE'] ?? '';
  if (Platform.isMacOS) {
    return p.join(
      home,
      'Library',
      'Application Support',
      'ComfyUI',
      'config.json',
    );
  }
  if (Platform.isWindows) {
    final roaming = env['APPDATA'] ?? p.join(home, 'AppData', 'Roaming');
    return p.join(roaming, 'ComfyUI', 'config.json');
  }
  final xdg = env['XDG_CONFIG_HOME'];
  final config = (xdg == null || xdg.isEmpty) ? p.join(home, '.config') : xdg;
  return p.join(config, 'ComfyUI', 'config.json');
}

/// The port ComfyUI Desktop is set to start its server on: its `config.json`
/// names the `basePath`, and `basePath/user/default/comfy.settings.json`
/// holds `Comfy.Server.LaunchArgs.port`. Null when either is missing or says
/// nothing; Desktop's own default (8000) is among [kComfyFallbackPorts].
/// Desktop moves to another port when that one is taken, so a running
/// server's `--port` is the better answer.
Future<int?> comfyDesktopPort({String? configPath}) async {
  final path = configPath ?? comfyDesktopConfigPath();
  if (path == null) return null;
  try {
    final config = jsonDecode(await File(path).readAsString());
    final base = config is Map ? config['basePath'] : null;
    if (base is! String || base.isEmpty) return null;
    final settings = jsonDecode(
      await File(
        p.join(base, 'user', 'default', 'comfy.settings.json'),
      ).readAsString(),
    );
    final args = settings is Map ? settings['Comfy.Server.LaunchArgs'] : null;
    final port = args is Map ? args['port'] : null;
    final value = port is int ? port : int.tryParse('$port');
    return (value != null && value > 0 && value < 65536) ? value : null;
  } on FileSystemException {
    return null;
  } on FormatException {
    return null;
  }
}

/// The `--port` of each ComfyUI running on this computer, in the order found.
List<int> comfyProcessPorts(List<ComfyProcessSnapshot> processes) {
  final ports = <int>[];
  for (final proc in processes) {
    final hints = comfyLaunchHints(
      proc.command,
      cwd: proc.cwd,
      executable: proc.executable,
    );
    final port = hints.port;
    if (port != null && !ports.contains(port)) ports.add(port);
  }
  return ports;
}

/// Where to look for ComfyUI, best first: the saved address, each running
/// server's port, ComfyUI Desktop's setting, then [fallbackPorts]. All but
/// the saved one are on this computer.
List<String> comfyUrlCandidates({
  required String saved,
  List<int> processPorts = const [],
  int? desktopPort,
  List<int> fallbackPorts = kComfyFallbackPorts,
}) {
  final out = <String>[];
  void add(String url) {
    final normal = ComfyUiService.ensureHttpScheme(url);
    if (normal.isNotEmpty && !out.contains(normal)) out.add(normal);
  }

  if (saved.trim().isNotEmpty) add(saved);
  for (final port in [...processPorts, ?desktopPort, ...fallbackPorts]) {
    add('http://127.0.0.1:$port');
  }
  return out;
}

/// Finds a ComfyUI that answers. The sources and the ports are injectable so
/// tests can point it at their own servers.
class ComfyUrlFinder {
  ComfyUrlFinder({
    Future<List<ComfyProcessSnapshot>> Function()? processes,
    Future<int?> Function()? desktopPort,
    this.fallbackPorts = kComfyFallbackPorts,
    this.timeout = kComfyProbeTimeout,
  }) : _processes = processes ?? scanComfyProcesses,
       _desktopPort = desktopPort ?? comfyDesktopPort;

  final Future<List<ComfyProcessSnapshot>> Function() _processes;
  final Future<int?> Function() _desktopPort;
  final List<int> fallbackPorts;
  final Duration timeout;

  /// Whether ComfyUI answers at [url].
  Future<bool> answers(String url) =>
      _outside(() => comfyAnswersAt(url, timeout: timeout));

  /// The scan and the asks are this computer's I/O with timeouts of their own.
  /// They run outside the caller's zone, so a widget's zone (a test's fake
  /// clock) neither holds them up nor is left holding their timers.
  static Future<T> _outside<T>(Future<T> Function() work) =>
      Zone.root.run(work);

  /// Every candidate is asked at once; the best one that answers wins. Null
  /// when none does.
  Future<String?> find(String saved) => _outside(() => _find(saved));

  Future<String?> _find(String saved) async {
    final (processes, desktop) = await (
      _processes().catchError((_) => const <ComfyProcessSnapshot>[]),
      _desktopPort().catchError((_) => null),
    ).wait;
    final candidates = comfyUrlCandidates(
      saved: saved,
      processPorts: comfyProcessPorts(processes),
      desktopPort: desktop,
      fallbackPorts: fallbackPorts,
    );
    final answers = await Future.wait([
      for (final url in candidates) comfyAnswersAt(url, timeout: timeout),
    ]);
    for (var i = 0; i < candidates.length; i++) {
      if (answers[i]) return candidates[i];
    }
    return null;
  }
}

/// What looking for ComfyUI concluded.
class ComfyRedial {
  const ComfyRedial({this.foundAt, this.adopted = false, this.saved = ''});

  /// The best address that answered, or null when none did.
  final String? foundAt;

  /// The found address was saved, because the person never gave one.
  final bool adopted;

  /// The saved address when it was looked from.
  final String saved;

  /// ComfyUI answers at the saved address (as it now is).
  bool get reachable => foundAt != null && (adopted || foundAt == saved);

  /// A ComfyUI answers somewhere else, and the saved address was given by the
  /// person, so it is offered rather than taken.
  String? get offer => (foundAt != null && !reachable) ? foundAt : null;
}

/// Looks for ComfyUI and, when the person never gave an address, switches to
/// the one that answers. An address they gave is kept; one found elsewhere
/// is returned as [ComfyRedial.offer].
Future<ComfyRedial> redialComfy(
  ImageGenSettings settings, {
  ComfyUrlFinder? finder,
}) async {
  final saved = ComfyUiService.ensureHttpScheme(settings.comfyUiUrl);
  final look = finder ?? ComfyUrlFinder();
  // The saved address answering is the common case: nothing to look for.
  if (await look.answers(saved)) {
    return ComfyRedial(foundAt: saved, saved: saved);
  }
  final found = await look.find(saved);
  if (found == null || found == saved) {
    return ComfyRedial(foundAt: found, saved: saved);
  }
  if (settings.comfyUiUrlExplicit) {
    return ComfyRedial(foundAt: found, saved: saved);
  }
  debugPrint('ComfyUI: found at $found, using it (was $saved)');
  await settings.adoptFoundComfyUiUrl(found);
  return ComfyRedial(foundAt: found, adopted: true, saved: saved);
}
