// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// What ComfyProcessProbe says on Windows, from the Win32 calls (no PowerShell,
// no helper process). Each answer is null when a call fails.

import 'package:path/path.dart' as p;

import 'comfy_process_probe.dart';
import 'windows_acl.dart';
import 'windows_api.dart';
import 'windows_api_security.dart';

const Win32Api kWin32 = Win32Api();
const Win32SecurityApi kWin32Security = Win32SecurityApi();

const int _afInet = 2;
const int _afInet6 = 23;

/// This user's SID.
Future<String?> windowsCurrentSid({
  Win32SecurityApi api = kWin32Security,
}) async => api.currentUserSid();

/// The processes of this user that listen on [port], IPv4 or IPv6. A process
/// that cannot be opened (access denied) is not this user's and is left out.
/// Null when a listener table cannot be read.
Future<Set<int>?> windowsListeningPids(
  int port, {
  Win32SecurityApi api = kWin32Security,
}) async {
  final me = api.currentUserSid();
  if (me == null) return null;
  final v4 = api.tcpListenerTable(_afInet);
  final v6 = api.tcpListenerTable(_afInet6);
  if (v4 == null || v6 == null) return null;
  final all = {
    ...parseTcpListenerTable(v4, port, v6: false),
    ...parseTcpListenerTable(v6, port, v6: true),
  };
  return {
    for (final pid in all)
      if (api.pidUserSid(pid) == me) pid,
  };
}

Future<bool?> windowsProcessIsMine(
  int pid, {
  Win32SecurityApi api = kWin32Security,
}) async {
  final me = api.currentUserSid();
  if (me == null) return null;
  return api.pidUserSid(pid) == me;
}

Future<DateTime?> windowsProcessStart(
  int pid, {
  Win32SecurityApi api = kWin32Security,
}) async => api.processStart(pid);

/// `\\?\` spelling of [path], for comparing with a handle's final path.
String windowsVerbatim(String path) {
  final full = p.windows.normalize(path);
  if (full.startsWith(r'\\?\')) return full;
  if (full.startsWith(r'\\')) return r'\\?\UNC\' + full.substring(2);
  return r'\\?\' + full;
}

/// True when [a] and [b] name the same place, ignoring case and a trailing
/// separator.
bool windowsSamePath(String a, String b) {
  String norm(String s) {
    var t = s.toLowerCase();
    while (t.length > 3 && t.endsWith(r'\')) {
      t = t.substring(0, t.length - 1);
    }
    return t;
  }

  return norm(a) == norm(b);
}

/// Owner, reparse state and who else may write [path], read through a handle
/// that opens the path itself and follows nothing.
Future<PathFacts?> windowsPathFacts(
  String path, {
  required bool folder,
  Win32Api files = kWin32,
  Win32SecurityApi security = kWin32Security,
}) async {
  final me = security.currentUserSid();
  if (me == null) return null;
  final (handle, err) = files.createFile(
    path,
    kReadControl | kFileReadAttributes,
    kShareRead | kShareWrite | kShareDelete,
    kOpenExisting,
    kFlagBackupSemantics | kFlagOpenReparsePoint,
  );
  if (handle == kInvalidHandle || err != 0) return null;
  try {
    final attributes = files.handleAttributes(handle);
    if (attributes == null) return null;
    // A reparse point (junction, symbolic link, mount point), or a path that
    // is not spelled as it resolves (a substituted drive, a short 8.3 name).
    final reparse = attributes & kAttributeReparsePoint != 0;
    final finalPath = files.finalPath(handle);
    if (finalPath == null) return null;
    final moved = !windowsSamePath(finalPath, windowsVerbatim(path));
    final (sec, secErr) = security.security(handle);
    if (sec == null || secErr != 0) return null;
    final aces = sec.aces;
    final verdict = windowsOwnerVerdict(sec.owner, me);
    return PathFacts(
      owner: sec.owner,
      ownerIsAdmin: verdict == WindowsOwnerVerdict.administrator,
      isLink: reparse || moved,
      othersCanWrite: aces == null
          ? null
          : windowsOthersCanWrite(aces, me: me, folder: folder),
      problem: aces == null
          ? 'Its ComfyUI-GGUF folder has no access list at all, so anyone can '
                'change it. Front Porch left its loader alone.'
          : null,
    );
  } finally {
    files.closeHandle(handle);
  }
}
