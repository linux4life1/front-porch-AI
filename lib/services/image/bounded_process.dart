// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// How long a look at this computer's processes (ps, lsof, PowerShell) or
/// ComfyUI Desktop's settings may take before it is given up on.
const kComfyLookupTimeout = Duration(seconds: 2);

/// Runs [executable] and returns what it printed, or null when it could not
/// start, exited with an error, or took longer than [timeout] (it is then
/// killed), so a hung tool cannot hold up finding ComfyUI. Runs outside the
/// caller's zone, so a widget's zone (a test's fake clock) is not left
/// holding its timer.
Future<String?> runBounded(
  String executable,
  List<String> arguments, {
  Duration timeout = kComfyLookupTimeout,
}) => Zone.root.run(() => _runBounded(executable, arguments, timeout));

Future<String?> _runBounded(
  String executable,
  List<String> arguments,
  Duration timeout,
) async {
  final Process process;
  try {
    process = await Process.start(executable, arguments);
  } on ProcessException catch (e) {
    debugPrint('$executable could not start: ${e.message}');
    return null;
  }
  final out = process.stdout.transform(systemEncoding.decoder).join();
  unawaited(process.stderr.drain<void>());
  try {
    final code = await process.exitCode.timeout(timeout);
    final text = await out;
    return code == 0 ? text : null;
  } on TimeoutException {
    process.kill(ProcessSignal.sigkill);
    debugPrint('$executable took over ${timeout.inSeconds} s; stopped it');
    return null;
  }
}
