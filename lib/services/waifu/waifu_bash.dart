// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:front_porch_ai/services/waifu/waifu_fs.dart';
import 'package:front_porch_ai/services/waifu/waifu_jail.dart';
import 'package:front_porch_ai/services/waifu/waifu_permissions.dart';
import 'package:front_porch_ai/services/waifu/waifu_tools.dart';

const kWaifuBashTimeout = Duration(seconds: 60);

const _waifuBashEnvironmentKeys = {
  'ANDROID_HOME',
  'ANDROID_SDK_ROOT',
  'CARGO_HOME',
  'COLORTERM',
  'COMSPEC',
  'CONDA_PREFIX',
  'DART_SDK',
  'DOTNET_ROOT',
  'FLUTTER_ROOT',
  'GEM_HOME',
  'GEM_PATH',
  'GOENV',
  'GOMODCACHE',
  'GOPATH',
  'GOROOT',
  'HOME',
  'JAVA_HOME',
  'LANG',
  'LANGUAGE',
  'LC_ALL',
  'LC_CTYPE',
  'LOGNAME',
  'NODE_PATH',
  'NVM_BIN',
  'NVM_DIR',
  'PATH',
  'PATHEXT',
  'PUB_CACHE',
  'PYTHONPATH',
  'RUSTUP_HOME',
  'SHELL',
  'SYSTEMROOT',
  'TEMP',
  'TERM',
  'TMP',
  'TMPDIR',
  'USER',
  'USERNAME',
  'USERPROFILE',
  'VIRTUAL_ENV',
  'WINDIR',
  'XDG_CACHE_HOME',
  'XDG_CONFIG_HOME',
  'XDG_DATA_HOME',
};

/// Development/runtime paths the child needs, without Front Porch API keys,
/// bearer tokens, keychain sockets, or arbitrary parent-process variables.
Map<String, String> waifuBashEnvironment(Map<String, String> source) {
  return Map.unmodifiable({
    for (final entry in source.entries)
      if (_waifuBashEnvironmentKeys.contains(entry.key.toUpperCase()))
        entry.key: entry.value,
  });
}

/// Runs a command from the sit-down folder. Folder-jail sessions refuse
/// outside paths; whole-disk sessions may `cd` elsewhere. Secret reads and
/// wipe/destroy-class commands stay denied in both.
class WaifuBash {
  WaifuBash(
    this.root, {
    this.timeout = kWaifuBashTimeout,
    this.pathMode = WaifuPathMode.folderJail,
    Map<String, String>? sourceEnvironment,
  }) : environment = waifuBashEnvironment(
         sourceEnvironment ?? Platform.environment,
       );

  final String root;
  final Duration timeout;
  final WaifuPathMode pathMode;
  final Map<String, String> environment;
  final Set<Process> _activeProcesses = {};
  int _abortEpoch = 0;

  Future<WaifuToolResult> run(Map<String, dynamic> args) async {
    final startedInEpoch = _abortEpoch;
    final command =
        args['command']?.toString() ?? args['cmd']?.toString() ?? '';
    if (command.trim().isEmpty) {
      return WaifuToolResult.error('bash: command is empty');
    }
    final blocked = waifuBashBlocked(command, workingDirectory: root);
    if (blocked != null) return WaifuToolResult.error(blocked);
    final secretBlock = await waifuBashResolvedSecretBlock(command, root);
    if (secretBlock != null) return WaifuToolResult.error(secretBlock);
    final wipeBlock = await waifuBashResolvedWipeBlock(command, root);
    if (wipeBlock != null) return WaifuToolResult.error(wipeBlock);
    final scopeBlock = await waifuBashScopeBlock(command, root, pathMode);
    if (scopeBlock != null) return WaifuToolResult.error(scopeBlock);
    if (_abortEpoch != startedInEpoch) {
      return WaifuToolResult.error('bash: stopped');
    }

    late final Process proc;
    try {
      proc = await Process.start(
        'bash',
        ['-c', command],
        workingDirectory: root,
        environment: environment,
        includeParentEnvironment: false,
        runInShell: false,
      );
    } catch (e) {
      return WaifuToolResult.error('bash: failed to start ($e)');
    }
    _activeProcesses.add(proc);
    if (_abortEpoch != startedInEpoch) proc.kill();

    final outFuture = proc.stdout.transform(utf8.decoder).join();
    final errFuture = proc.stderr.transform(utf8.decoder).join();

    try {
      final code = await proc.exitCode.timeout(timeout);
      final stdout = await outFuture;
      final stderr = await errFuture;
      final body = _clip(
        'exit $code\n$stdout${stderr.isEmpty ? '' : '\n$stderr'}',
      );
      return WaifuToolResult(ok: code == 0, output: body);
    } on TimeoutException {
      proc.kill();
      return WaifuToolResult.error(
        'bash: timeout (${timeout.inMilliseconds}ms)',
      );
    } finally {
      _activeProcesses.remove(proc);
    }
  }

  void abort() {
    _abortEpoch++;
    for (final process in List<Process>.from(_activeProcesses)) {
      process.kill();
    }
  }
}

String? waifuBashBlocked(String command, {String? workingDirectory}) =>
    waifuDeniedCommand(command, workingDirectory: workingDirectory);

/// Resolve path-looking command words before spawn so an innocent-looking
/// symlink cannot turn `cat notes` into a read of `.env`, `.ssh`, or `.aws`.
Future<String?> waifuBashResolvedSecretBlock(
  String command,
  String root,
) async {
  for (final word in waifuShellWords(command)) {
    final candidate = word.contains('=') ? word.split('=').last : word;
    if ((word.startsWith('-') && !word.contains('=')) ||
        candidate.contains(r'$') ||
        word.contains('*') ||
        word.contains('?')) {
      continue;
    }
    final hit = await WaifuJail.resolveLive(
      root,
      candidate,
      pathMode: WaifuPathMode.wholeDisk,
    );
    if (hit.ok && waifuIsProtectedSecretPath(hit.path!)) {
      return 'denied: .env, .ssh, and .aws secrets stay off the workbench';
    }
  }
  return null;
}

/// Re-check existing command paths after symlink resolution. This closes the
/// whole-disk case where a harmless-looking relative target resolves to the
/// sit-down folder's parent or another protected root.
Future<String?> waifuBashResolvedWipeBlock(String command, String root) async {
  final lower = command.toLowerCase();
  final words = waifuShellWords(lower);
  final recursiveOperation =
      (words.any((word) => word == 'rm' || word.endsWith('/rm')) &&
          (words.contains('--recursive') ||
              words.any(
                (word) =>
                    word.startsWith('-') &&
                    !word.startsWith('--') &&
                    word.contains('r'),
              ))) ||
      (words.any((word) => word == 'find' || word.endsWith('/find')) &&
          words.contains('-delete')) ||
      lower.contains('shutil.rmtree') ||
      ((words.any(
            (word) =>
                word == 'chmod' ||
                word.endsWith('/chmod') ||
                word == 'chown' ||
                word.endsWith('/chown'),
          )) &&
          (words.contains('--recursive') ||
              words.any(
                (word) =>
                    word.startsWith('-') &&
                    !word.startsWith('--') &&
                    word.contains('r'),
              )));
  if (!recursiveOperation) return null;
  for (final word in words) {
    if (word.startsWith('-') ||
        word.contains(r'$') ||
        word.contains('*') ||
        word.contains('?') ||
        word.contains('=')) {
      continue;
    }
    final hit = await WaifuJail.resolveLive(
      root,
      word,
      pathMode: WaifuPathMode.wholeDisk,
    );
    if (!hit.ok) continue;
    if (waifuDeniedCommand('rm -r "${hit.path}"', workingDirectory: root) !=
        null) {
      return 'denied: recursive operation resolves to a protected root or '
          'sit-down ancestor';
    }
  }
  return null;
}

/// Folder-jail bash preflight. Command names may live outside the project;
/// model-supplied file arguments, redirects, `cd`, and symlink targets may not.
Future<String?> waifuBashScopeBlock(
  String command,
  String root,
  WaifuPathMode pathMode,
) async {
  if (pathMode == WaifuPathMode.wholeDisk) return null;
  for (final segment in command.split(RegExp(r'(?:&&|\|\||[;\n])'))) {
    final words = waifuShellWords(segment);
    for (var i = 0; i < words.length; i++) {
      final word = words[i];
      if (word == 'cd' || word == 'pushd') {
        final destinations = words
            .skip(i + 1)
            .where((candidate) => !candidate.startsWith('-'));
        if (destinations.isEmpty) {
          return 'Folder jail: bash paths and cd cannot leave the sit-down '
              'folder';
        }
      }
      final candidate = word.contains('=') ? word.split('=').last : word;
      if (i == 0 ||
          (word.startsWith('-') && !word.contains('=')) ||
          candidate.contains(r'$')) {
        continue;
      }
      final hit = await WaifuJail.resolveLive(
        root,
        candidate,
        pathMode: WaifuPathMode.folderJail,
      );
      if (!hit.ok) {
        return 'Folder jail: bash paths and cd cannot leave the sit-down '
            'folder';
      }
    }
  }
  return null;
}

String _clip(String s) {
  if (s.length <= kWaifuBashClipChars) return s;
  return '${s.substring(0, kWaifuBashClipChars)}\n…(clipped)';
}
