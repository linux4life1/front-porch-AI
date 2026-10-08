// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// The rules for reading a Windows security descriptor, apart from the calls
// that fetch one, so they can be checked on any machine.

/// Well-known security identifiers.
const String kSidSystem = 'S-1-5-18';
const String kSidAdministrators = 'S-1-5-32-544';
const String kSidOwnerRights = 'S-1-3-4';
const String kSidTrustedInstaller =
    'S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464';

/// Owners that are not this user but are the operating system's own. A folder
/// they own is not refused as "someone else's": it is one only an
/// administrator may change, so the person is told to update it by hand.
const Set<String> kWindowsAdminSids = {
  kSidSystem,
  kSidAdministrators,
  kSidTrustedInstaller,
};

const int kAceAllowed = 0;
const int kAceDenied = 1;

const int kAceObjectInherit = 0x1;
const int kAceInheritOnly = 0x8;

/// The rights that let a principal change a folder (add files, delete
/// children, rewrite its permissions) or a file.
const int kWindowsFolderWriteMask = 0x500D0046;
const int kWindowsFileWriteMask = 0x500D0006;

/// One access-control entry: its type, flags, mask and the SID it names.
class WindowsAce {
  const WindowsAce({
    required this.type,
    required this.flags,
    required this.mask,
    required this.sid,
  });

  final int type;
  final int flags;
  final int mask;
  final String sid;
}

/// What MapGenericMask does with the generic bits of a file mask.
int mapGenericFileMask(int mask) {
  const genericRead = 0x80000000;
  const genericWrite = 0x40000000;
  const genericExecute = 0x20000000;
  const genericAll = 0x10000000;
  const fileRead = 0x120089;
  const fileWrite = 0x120116;
  const fileExecute = 0x1200A0;
  const fileAll = 0x1F01FF;
  var out = mask & ~(genericRead | genericWrite | genericExecute | genericAll);
  if (mask & genericRead != 0) out |= fileRead;
  if (mask & genericWrite != 0) out |= fileWrite;
  if (mask & genericExecute != 0) out |= fileExecute;
  if (mask & genericAll != 0) out |= fileAll;
  return out;
}

/// True when [sid] is one of the identities that are not "other users":
/// this user, the system, the administrators, TrustedInstaller and OWNER
/// RIGHTS.
bool windowsSidIsTrusted(String sid, String me) =>
    sid == me ||
    sid == kSidSystem ||
    sid == kSidAdministrators ||
    sid == kSidTrustedInstaller ||
    sid == kSidOwnerRights;

/// True when a principal other than [me] and the trusted ones is allowed to
/// write, judged from the allow entries only (a deny entry is ignored: it
/// could be removed by anyone who may change permissions).
///
/// For a folder, an entry that is inherit-only still counts when it is
/// inherited by files, because the files made in it (the temp file, the
/// backup) will carry it.
bool windowsOthersCanWrite(
  List<WindowsAce> aces, {
  required String me,
  required bool folder,
}) {
  final want = folder ? kWindowsFolderWriteMask : kWindowsFileWriteMask;
  for (final ace in aces) {
    if (ace.type != kAceAllowed) continue;
    if (windowsSidIsTrusted(ace.sid, me)) continue;
    final inheritOnly = ace.flags & kAceInheritOnly != 0;
    if (inheritOnly && !(folder && ace.flags & kAceObjectInherit != 0)) {
      continue;
    }
    if (mapGenericFileMask(ace.mask) & want != 0) return true;
  }
  return false;
}

/// What a security descriptor says about who may use a path.
enum WindowsOwnerVerdict { mine, administrator, someoneElse }

WindowsOwnerVerdict windowsOwnerVerdict(String owner, String me) {
  if (owner == me) return WindowsOwnerVerdict.mine;
  if (kWindowsAdminSids.contains(owner)) {
    return WindowsOwnerVerdict.administrator;
  }
  return WindowsOwnerVerdict.someoneElse;
}
