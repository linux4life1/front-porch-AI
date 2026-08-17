// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Who may write / report a Stoop comment. Fail-closed: omitted emailVerified
// is NOT verified. Do NOT reuse stoopCanReport — that helper inherits the
// user model's default-true (older server omitted the field).

import 'package:front_porch_ai/services/backporch/backporch_api.dart';
import 'package:front_porch_ai/services/backporch/backporch_user.dart';
import 'package:front_porch_ai/services/backporch/stoop_comment.dart';
import 'package:unorm_dart/unorm_dart.dart' as unorm;

/// Hard cap on a comment / reply body (plain text).
const int kStoopCommentMaxLength = 1000;

// http(s), www, mailto, protocol-relative, discord.gg, dotted IPv4, and
// bare hosts (example.com, t.me, bit.ly) with or without a path. 1000-char
// cap is independent of this check. Link-check copy only (stored body
// unchanged): percent-decode until stable (cap 16; Uri.decodeComponent;
// invalid swallow-and-stop) plus %uXXXX; then HTML numeric-entity decode
// (&#\d{1,7};? / &#x[0-9a-fA-F]{1,6};?, leading zeros ok; consume ';'
// if present, else only when the next char cannot continue the number)
// emitting the code point (skip 0 / surrogates / > U+10FFFF); named
// dot aliases &period/&Dot/&fullstop/&middot/&centerdot (case-
// insensitive, optional semicolon); and \. → .; then strip
// \p{Cf}+\p{Cc} so decode-then-Cc dies (%00, ZWSP, soft hyphen); map
// U+02D9 before NFKC (NFKC turns it into space+0307), then the
// unicode-dot map, then NFKC (unorm_dart — already a dep), then the
// dot map again.
// Dot map: U+3002/FF61/FF0E/2024/FE52/30FB/00B7/2027/2219/
// 22C5/2E31/FF65/2022/06D4/066B/0701/16EB/02D9/A4F8. Skipped comma-likes
// U+3001/FF64/FF0C (hello、world). Cheap residuals: file://, javascript:,
// data:, tg://, ftp://, ws(s)://, whatsapp://, localhost, plus word-start
// schemes tel:/sms:/magnet:/skype:/bitcoin:/geo:/callto:/whatsapp:/tg:/
// facetime:/discord:/steam:/itms-apps:/intent:/maps:/line: (not prose
// see:/note:).
// IPv6 (bracketed, compressed ::, colon-hex with a-f, 8-group) is
// rejected; HH:MM:SS is not.
final _linkRe = RegExp(
  r'(https?:\/\/|ftps?:\/\/|wss?:\/\/|whatsapp:\/\/|[a-z][a-z0-9+.-]*:\/\/|www\.|mailto:|file:\/\/|javascript:|data:|tg:\/\/|(?:^|[\s<(])\/\/[a-z0-9]|discord\.gg|localhost|(?:\d{1,3}\.){3}\d{1,3}|[a-z0-9][a-z0-9.-]*\.[a-z]{2,})',
  caseSensitive: false,
);

final _formatCharsRe = RegExp(r'[\p{Cf}\p{Cc}]', unicode: true);

// Word-start / start-of-string only — do not reject "see:" / "note:".
final _schemePrefixRe = RegExp(
  r'\b(?:tel|sms|magnet|skype|bitcoin|geo|callto|whatsapp|tg|facetime|discord|steam|itms-apps|intent|maps|line):',
  caseSensitive: false,
);

final _unicodeDotRe = RegExp(
  '[\u3002\uff61\uff0e\u2024\ufe52\u30fb\u00b7\u2027\u2219\u22c5\u2e31\uff65\u2022\u06d4\u066b\u0701\u16eb\u02d9\ua4f8]',
);

// :: compression, [hex:…] brackets, or 8 hex groups (7 colons).
final _ipv6EasyRe = RegExp(
  r'(::|\[[0-9a-f:]+\]|(?:[0-9a-f]{1,4}:){7}[0-9a-f]{1,4})',
  caseSensitive: false,
);

// Colon-separated hex groups; caller requires an a-f so 10:30:45 is safe.
final _colonHexTokenRe = RegExp(
  r'[0-9a-f]{0,4}(?::[0-9a-f]{1,4}){1,7}',
  caseSensitive: false,
);

final _hexLetterRe = RegExp(r'[a-f]', caseSensitive: false);

// IDN host (пример.рф). ASCII hosts stay on the TLD arm of _linkRe.
final _idnHostRe = RegExp(
  r'[\p{L}\p{N}][\p{L}\p{N}.-]*\.[\p{L}]{2,}',
  unicode: true,
);

// Hex IPv4 (0xCB007109) and short 100-255.x (127.1). Skips 3.14.
final _hexOrShortIpv4Re = RegExp(
  r'(?:\b0x[0-9a-f]{1,8}\b|\b(?:1\d{2}|2[0-4]\d|25[0-5])\.\d{1,3}\b)',
  caseSensitive: false,
);

final _percentUxxxxRe = RegExp(r'%u([0-9a-fA-F]{4})', caseSensitive: false);

final _htmlNumericEntityRe = RegExp(
  r'&#(?:x([0-9a-fA-F]{1,6})|(\d{1,7}));?',
  caseSensitive: false,
);

final _htmlNamedDotRe = RegExp(
  r'&(centerdot|fullstop|period|middot|dot);?',
  caseSensitive: false,
);

bool _isAsciiDigitUnit(int c) => c >= 0x30 && c <= 0x39;

bool _isAsciiHexUnit(int c) =>
    _isAsciiDigitUnit(c) ||
    (c >= 0x41 && c <= 0x46) ||
    (c >= 0x61 && c <= 0x66);

/// Numeric + named-dot HTML decode for the link-check copy only.
/// Decimal `&#\d{1,7};?` and hex `&#x[0-9a-fA-F]{1,6};?` (leading zeros
/// ok). Optional semicolon: consume it when present; when absent, only
/// decode if the next char cannot continue the number. Emit the code
/// point; skip 0 / surrogates / > U+10FFFF. Named aliases (case-
/// insensitive, optional semicolon) that are dots: period, Dot,
/// fullstop, middot, centerdot. Also `\.` → `.`.
String _decodeHtmlForLinkCheck(String text) {
  final numeric = text.replaceAllMapped(_htmlNumericEntityRe, (m) {
    final raw = m.group(0)!;
    final hex = m.group(1);
    final hadSemi = raw.endsWith(';');
    if (!hadSemi && m.end < text.length) {
      final next = text.codeUnitAt(m.end);
      if (hex != null) {
        if (_isAsciiHexUnit(next)) return raw;
      } else if (_isAsciiDigitUnit(next)) {
        return raw;
      }
    }
    final cp = hex != null
        ? int.parse(hex, radix: 16)
        : int.parse(m.group(2)!);
    if (cp <= 0 || cp > 0x10FFFF || (cp >= 0xD800 && cp <= 0xDFFF)) {
      return '';
    }
    return String.fromCharCode(cp);
  });
  return numeric
      .replaceAllMapped(_htmlNamedDotRe, (_) => '.')
      .replaceAll(r'\.', '.');
}

String _decodePercentUxxxx(String text) {
  return text.replaceAllMapped(_percentUxxxxRe, (m) {
    return String.fromCharCode(int.parse(m.group(1)!, radix: 16));
  });
}

String _percentDecodeForLinkCheck(String text) {
  var current = text;
  for (var i = 0; i < 16; i++) {
    var next = _decodePercentUxxxx(current);
    try {
      next = Uri.decodeComponent(next);
    } catch (_) {
      if (next == current) break;
      current = next;
      continue;
    }
    if (next == current) break;
    current = next;
  }
  return current;
}

String _normalizeStoopCommentForLinkCheck(String body) {
  var text = _percentDecodeForLinkCheck(body);
  text = _decodeHtmlForLinkCheck(text);
  text = text.replaceAll(_formatCharsRe, '');
  text = text.replaceAll('\u02d9', '.');
  text = text.replaceAll(_unicodeDotRe, '.');
  text = unorm.nfkc(text);
  return text.replaceAll(_unicodeDotRe, '.');
}

bool _hasIpv6(String text) {
  if (_ipv6EasyRe.hasMatch(text)) return true;
  for (final m in _colonHexTokenRe.allMatches(text)) {
    if (_hexLetterRe.hasMatch(m.group(0)!)) return true;
  }
  return false;
}

/// True when [body] contains a URL. Comments and replies are plain text.
bool stoopCommentBodyHasLink(String body) {
  final text = _normalizeStoopCommentForLinkCheck(body);
  return _linkRe.hasMatch(text) ||
      _schemePrefixRe.hasMatch(text) ||
      _hasIpv6(text) ||
      _idnHostRe.hasMatch(text) ||
      _hexOrShortIpv4Re.hasMatch(text);
}

/// True ONLY when [user] is signed in and email is *explicitly* verified.
///
/// - `user == null` → false (guest)
/// - omitted / unknown `emailVerified` → false (unlike [stoopCanReport])
/// - `emailVerified == false` → false
/// - a pending change-email is not verified
/// - accepting the AUP is not a substitute for email verification
bool stoopCanComment(BackporchUser? user) {
  if (user == null) return false;
  final pending = user.pendingEmail?.trim();
  if (pending != null && pending.isNotEmpty) return false;
  if (!user.emailVerifiedKnown) return false;
  return user.emailVerified == true;
}

/// Card owner only, and only on someone else's top-level comment that has
/// no *live* reply. A deleted tombstone does not block — replace is hide
/// then [StoopCommentsClient.createReply]. Hub/mod does not get a public
/// reply voice unless they own the card. Same write gate as comments
/// ([stoopCanComment]).
bool stoopCanReplyToComment({
  required StoopComment comment,
  required BackporchUser? user,
  String? cardOwnerId,
}) {
  if (!stoopCanComment(user)) return false;
  if (cardOwnerId == null || user!.id != cardOwnerId) return false;
  if (comment.authorId == user.id) return false;
  if (comment.deleted) return false;
  final reply = comment.reply;
  if (reply != null && !reply.deleted) return false;
  return true;
}

/// Author, card owner, or hub/moderator may soft-delete.
bool stoopCanDeleteComment({
  required StoopComment comment,
  required BackporchUser? user,
  String? cardOwnerId,
  bool canModerate = false,
}) {
  if (user == null) return false;
  if (comment.deleted) return false;
  if (canModerate || user.isModerator) return true;
  if (comment.authorId == user.id) return true;
  if (cardOwnerId != null && cardOwnerId == user.id) return true;
  return false;
}

/// Reply author, card owner, or hub/moderator may soft-delete the reply.
/// Hub/mod can delete; they still do not get a public reply voice.
bool stoopCanDeleteReply({
  required StoopCommentReply reply,
  required BackporchUser? user,
  String? cardOwnerId,
  bool canModerate = false,
}) {
  if (user == null) return false;
  if (reply.deleted) return false;
  if (canModerate || user.isModerator) return true;
  if (reply.authorId == user.id) return true;
  if (cardOwnerId != null && cardOwnerId == user.id) return true;
  return false;
}

/// Signed-in + fail-closed verified + not own comment. Hidden UI is not
/// the gate — the client must still 403 if this is false.
bool stoopCanReportComment({
  required StoopComment comment,
  required BackporchUser? user,
}) {
  if (!stoopCanComment(user)) return false;
  if (comment.deleted) return false;
  if (comment.authorId == user!.id) return false;
  return true;
}

/// Same write gate as comments. Hidden on your own reply.
bool stoopCanReportReply({
  required StoopCommentReply reply,
  required BackporchUser? user,
}) {
  if (!stoopCanComment(user)) return false;
  if (reply.deleted) return false;
  if (reply.authorId == user!.id) return false;
  return true;
}

/// Map create/delete/report failures to a short sentence.
String stoopCommentFailureMessage(Object error) {
  if (error is BackporchApiException) {
    switch (error.code) {
      case 'email_not_verified':
        return 'Confirm email to comment.';
      case 'duplicate_comment':
      case 'duplicate':
        return 'You already posted that.';
      case 'reply_exists':
        return 'This comment already has a reply.';
      case 'too_many_comments':
      case 'too_many_reports':
        return 'You’re commenting too fast — please wait a while.';
      case 'blank_comment':
        return 'Write something first.';
      case 'too_long':
        return 'Comments can be at most 1000 characters.';
      case 'no_links':
        return 'Links aren’t allowed.';
      case 'cannot_report_own':
        return 'You can’t report your own comment.';
      case 'not_card_owner':
        return 'Only the card creator can reply.';
      case 'comment_deleted':
      case 'parent_deleted':
      case 'parent_gone':
        return 'That comment is gone.';
      case 'comments_disabled':
        return 'Comments are turned off on this card.';
      case 'unauthorized':
        return 'Sign in to comment.';
    }
    if (error.statusCode == 429) {
      return 'You’re commenting too fast — please wait a while.';
    }
    if (error.statusCode == 409) {
      return 'You already posted that.';
    }
  }
  return 'Couldn’t post that comment. Try again.';
}

/// Relative time for a comment row. [now] is injectable so goldens stay still.
String stoopCommentRelativeTime(DateTime createdAt, DateTime now) {
  final delta = now.toUtc().difference(createdAt.toUtc());
  if (delta.isNegative || delta.inSeconds < 45) return 'just now';
  if (delta.inMinutes < 60) return '${delta.inMinutes}m ago';
  if (delta.inHours < 24) return '${delta.inHours}h ago';
  if (delta.inDays < 30) return '${delta.inDays}d ago';
  final d = createdAt.toUtc();
  final mm = d.month.toString().padLeft(2, '0');
  final dd = d.day.toString().padLeft(2, '0');
  return '${d.year}-$mm-$dd';
}
