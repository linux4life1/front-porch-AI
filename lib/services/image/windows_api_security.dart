// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// The Win32 calls that read who owns a path and who may change it, who a
// process is, when it started, and who listens on a port. Same rules as
// windows_api.dart: each call is a method, the libraries open on first use.

import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'windows_acl.dart';
import 'windows_api.dart';

class Win32SecurityApi {
  const Win32SecurityApi();

  static final DynamicLibrary _k32 = DynamicLibrary.open('kernel32.dll');
  static final DynamicLibrary _adv = DynamicLibrary.open('advapi32.dll');
  static final DynamicLibrary _ip = DynamicLibrary.open('iphlpapi.dll');

  static final _closeHandle = _k32
      .lookupFunction<Int32 Function(IntPtr), int Function(int)>(
        'CloseHandle',
        isLeaf: true,
      );
  static final _openProcess = _k32
      .lookupFunction<
        IntPtr Function(Uint32, Int32, Uint32),
        int Function(int, int, int)
      >('OpenProcess', isLeaf: true);
  static final _currentProcess = _k32
      .lookupFunction<IntPtr Function(), int Function()>(
        'GetCurrentProcess',
        isLeaf: true,
      );
  static final _processTimes = _k32
      .lookupFunction<
        Int32 Function(
          IntPtr,
          Pointer<Uint64>,
          Pointer<Uint64>,
          Pointer<Uint64>,
          Pointer<Uint64>,
        ),
        int Function(
          int,
          Pointer<Uint64>,
          Pointer<Uint64>,
          Pointer<Uint64>,
          Pointer<Uint64>,
        )
      >('GetProcessTimes', isLeaf: true);
  static final _localFree = _k32
      .lookupFunction<
        Pointer<Void> Function(Pointer<Void>),
        Pointer<Void> Function(Pointer<Void>)
      >('LocalFree', isLeaf: true);
  static final _openToken = _adv
      .lookupFunction<
        Int32 Function(IntPtr, Uint32, Pointer<IntPtr>),
        int Function(int, int, Pointer<IntPtr>)
      >('OpenProcessToken', isLeaf: true);
  static final _tokenInfo = _adv
      .lookupFunction<
        Int32 Function(IntPtr, Int32, Pointer<Uint8>, Uint32, Pointer<Uint32>),
        int Function(int, int, Pointer<Uint8>, int, Pointer<Uint32>)
      >('GetTokenInformation', isLeaf: true);
  static final _securityInfo = _adv
      .lookupFunction<
        Uint32 Function(
          IntPtr,
          Int32,
          Uint32,
          Pointer<Pointer<Void>>,
          Pointer<Pointer<Void>>,
          Pointer<Pointer<Void>>,
          Pointer<Pointer<Void>>,
          Pointer<Pointer<Void>>,
        ),
        int Function(
          int,
          int,
          int,
          Pointer<Pointer<Void>>,
          Pointer<Pointer<Void>>,
          Pointer<Pointer<Void>>,
          Pointer<Pointer<Void>>,
          Pointer<Pointer<Void>>,
        )
      >('GetSecurityInfo', isLeaf: true);
  static final _aclInfo = _adv
      .lookupFunction<
        Int32 Function(Pointer<Void>, Pointer<Uint8>, Uint32, Int32),
        int Function(Pointer<Void>, Pointer<Uint8>, int, int)
      >('GetAclInformation', isLeaf: true);
  static final _getAce = _adv
      .lookupFunction<
        Int32 Function(Pointer<Void>, Uint32, Pointer<Pointer<Void>>),
        int Function(Pointer<Void>, int, Pointer<Pointer<Void>>)
      >('GetAce', isLeaf: true);
  static final _sidToString = _adv
      .lookupFunction<
        Int32 Function(Pointer<Void>, Pointer<Pointer<Utf16>>),
        int Function(Pointer<Void>, Pointer<Pointer<Utf16>>)
      >('ConvertSidToStringSidW', isLeaf: true);
  static final _tcpTable = _ip
      .lookupFunction<
        Uint32 Function(
          Pointer<Uint8>,
          Pointer<Uint32>,
          Int32,
          Uint32,
          Int32,
          Uint32,
        ),
        int Function(Pointer<Uint8>, Pointer<Uint32>, int, int, int, int)
      >('GetExtendedTcpTable', isLeaf: true);

  /// The owner and DACL of the object behind [handle]. Null on failure.
  (WindowsSecurity?, int err) security(int handle) {
    final owner = calloc<Pointer<Void>>();
    final dacl = calloc<Pointer<Void>>();
    final sd = calloc<Pointer<Void>>();
    try {
      // File object, owner and DACL.
      final err = _securityInfo(
        handle,
        1,
        0x1 | 0x4,
        owner,
        nullptr,
        dacl,
        nullptr,
        sd,
      );
      if (err != 0) return (null, err);
      try {
        final ownerSid = _sidString(owner.value);
        if (ownerSid == null) return (null, 1);
        if (dacl.value == nullptr) {
          return (WindowsSecurity(owner: ownerSid, aces: null), 0);
        }
        final aces = _readAcl(dacl.value);
        if (aces == null) return (null, 1);
        return (WindowsSecurity(owner: ownerSid, aces: aces), 0);
      } finally {
        _localFree(sd.value);
      }
    } finally {
      calloc.free(owner);
      calloc.free(dacl);
      calloc.free(sd);
    }
  }

  List<WindowsAce>? _readAcl(Pointer<Void> acl) {
    final info = calloc<Uint8>(12);
    try {
      if (_aclInfo(acl, info, 12, 2) == 0) return null;
      final count = ByteData.sublistView(
        info.asTypedList(12),
      ).getUint32(0, Endian.little);
      final out = <WindowsAce>[];
      final ace = calloc<Pointer<Void>>();
      try {
        for (var i = 0; i < count; i++) {
          if (_getAce(acl, i, ace) == 0) return null;
          final at = ace.value.cast<Uint8>();
          final head = ByteData.sublistView(at.asTypedList(8));
          final type = head.getUint8(0);
          final size = head.getUint16(2, Endian.little);
          // Types that carry a plain SID after the mask (allowed, denied and
          // their callback forms). Others cannot be read, so they are kept as
          // an entry that names no one.
          const plain = {0, 1, 9, 10};
          if (!plain.contains(type) || size < 12) {
            out.add(
              WindowsAce(type: type, flags: head.getUint8(1), mask: 0, sid: ''),
            );
            continue;
          }
          final sid = _sidString((at + 8).cast<Void>());
          if (sid == null) return null;
          out.add(
            WindowsAce(
              type: type == 9 ? 0 : (type == 10 ? 1 : type),
              flags: head.getUint8(1),
              mask: head.getUint32(4, Endian.little),
              sid: sid,
            ),
          );
        }
      } finally {
        calloc.free(ace);
      }
      return out;
    } finally {
      calloc.free(info);
    }
  }

  String? _sidString(Pointer<Void> sid) {
    final out = calloc<Pointer<Utf16>>();
    try {
      if (_sidToString(sid, out) == 0) return null;
      try {
        return out.value.toDartString();
      } finally {
        _localFree(out.value.cast<Void>());
      }
    } finally {
      calloc.free(out);
    }
  }

  /// The user SID of the process token behind [process] (a process handle).
  String? processUserSid(int process) {
    final tok = calloc<IntPtr>();
    try {
      if (_openToken(process, 0x8, tok) == 0) return null;
      try {
        final need = calloc<Uint32>();
        try {
          _tokenInfo(tok.value, 1, nullptr, 0, need);
          final size = need.value;
          if (size == 0 || size > 4096) return null;
          final buf = calloc<Uint8>(size);
          try {
            if (_tokenInfo(tok.value, 1, buf, size, need) == 0) return null;
            // TOKEN_USER: a pointer to the SID first.
            final sidPtr = Pointer<Pointer<Void>>.fromAddress(
              buf.address,
            ).value;
            return _sidString(sidPtr);
          } finally {
            calloc.free(buf);
          }
        } finally {
          calloc.free(need);
        }
      } finally {
        _closeHandle(tok.value);
      }
    } finally {
      calloc.free(tok);
    }
  }

  String? currentUserSid() => processUserSid(_currentProcess());

  /// The user SID of process [pid]; null when it cannot be opened (access
  /// denied: it is not ours).
  String? pidUserSid(int pid) {
    final h = _openProcess(0x1000, 0, pid);
    if (h == 0) return null;
    try {
      return processUserSid(h);
    } finally {
      _closeHandle(h);
    }
  }

  DateTime? processStart(int pid) {
    final h = _openProcess(0x1000, 0, pid);
    if (h == 0) return null;
    final t = calloc<Uint64>(4);
    try {
      if (_processTimes(h, t, t + 1, t + 2, t + 3) == 0) return null;
      final micros = t.value ~/ 10 - 11644473600 * 1000000;
      return DateTime.fromMicrosecondsSinceEpoch(micros, isUtc: true);
    } finally {
      calloc.free(t);
      _closeHandle(h);
    }
  }

  /// The listening TCP table for [family] (2 = IPv4, 23 = IPv6), as bytes.
  Uint8List? tcpListenerTable(int family) {
    var size = 0;
    final sizePtr = calloc<Uint32>();
    try {
      for (var attempt = 0; attempt < 6; attempt++) {
        sizePtr.value = size;
        final buf = size == 0 ? nullptr.cast<Uint8>() : calloc<Uint8>(size);
        try {
          // Listener table, owner process ids.
          final err = _tcpTable(buf, sizePtr, 0, family, 3, 0);
          if (err == 0) {
            return Uint8List.fromList(buf.asTypedList(sizePtr.value));
          }
          if (err != kErrorInsufficientBuffer) return null;
          size = sizePtr.value + 64;
        } finally {
          if (buf != nullptr) calloc.free(buf);
        }
      }
      return null;
    } finally {
      calloc.free(sizePtr);
    }
  }
}

/// The process ids listening on [port] in a `MIB_TCPTABLE_OWNER_PID`
/// ([v6] false) or `MIB_TCP6TABLE_OWNER_PID` ([v6] true) table.
Set<int> parseTcpListenerTable(Uint8List table, int port, {required bool v6}) {
  final data = ByteData.sublistView(table);
  if (table.length < 4) return {};
  final count = data.getUint32(0, Endian.little);
  final row = v6 ? 56 : 24;
  final out = <int>{};
  for (var i = 0; i < count; i++) {
    final at = 4 + i * row;
    if (at + row > table.length) break;
    final portField = data.getUint32(at + (v6 ? 20 : 8), Endian.little);
    final networkOrder = ((portField & 0xFF) << 8) | ((portField >> 8) & 0xFF);
    if (networkOrder != port) continue;
    out.add(data.getUint32(at + (v6 ? 52 : 20), Endian.little));
  }
  return out;
}
