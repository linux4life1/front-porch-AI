// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

/// Whether [error] is the backend refusing the request outright: an
/// auth, billing or permission answer (HTTP 401 / 402 / 403, or a provider
/// message about the key, billing, balance, subscription, quota or
/// permission). Asking again gives the same answer and, on a pay-per-call
/// key, can cost money, so the creator does not retry these.
///
/// The remote backend throws `Exception('API error: <provider message>')`
/// (the message is `HTTP <code>` when the body was empty), so this reads
/// the text. Only backend answers count: a dropped or refused connection
/// is not a refusal.
bool isBackendRefusal(Object error) {
  final text = error.toString();
  if (_statusRefusal.hasMatch(text)) return true;
  if (!text.contains('API error')) return false;
  return _refusalWords.hasMatch(text);
}

/// The provider's own words for [error], without the exception prefixes.
String refusalMessage(Object error) => error
    .toString()
    .replaceFirst(RegExp(r'^Exception:\s*'), '')
    .replaceFirst(RegExp(r'^API error:\s*'), '')
    .trim();

final _statusRefusal = RegExp(
  r'\b(HTTP|status|code)\s*:?\s*40[123]\b',
  caseSensitive: false,
);

final _refusalWords = RegExp(
  r'api[ _-]?key|unauthori[sz]ed|forbidden|billing|balance|subscription|'
  r'quota|insufficient (credits?|funds)|payment required|permission|'
  r'not allowed to use',
  caseSensitive: false,
);
