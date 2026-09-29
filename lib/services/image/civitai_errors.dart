// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

/// Why a CivitAI download did not finish. Each kind has its own wording and
/// a stable [CivitaiDownloadException.code] the phone can branch on.
enum CivitaiFailure {
  keyMissing,
  keyRefused,
  locked,
  notFound,
  stalled,
  short,
  sizeMismatch,
  tooLarge,
  diskFull,
  hashMismatch,
  exists,
  nameTaken,
  busy,
  tooMany,
  cancelled,
  redirect,
  unsafe,
  network,
  http,
}

class CivitaiDownloadException implements Exception {
  const CivitaiDownloadException(this.kind, [this.detail = '']);

  final CivitaiFailure kind;

  /// Extra words for the kinds that carry one (a file name, an HTTP status).
  final String detail;

  String get code => switch (kind) {
    CivitaiFailure.keyMissing => 'key_missing',
    CivitaiFailure.keyRefused => 'key_refused',
    CivitaiFailure.locked => 'locked',
    CivitaiFailure.notFound => 'not_found',
    CivitaiFailure.stalled => 'stalled',
    CivitaiFailure.short => 'short',
    CivitaiFailure.sizeMismatch => 'size_mismatch',
    CivitaiFailure.tooLarge => 'too_large',
    CivitaiFailure.diskFull => 'disk_full',
    CivitaiFailure.hashMismatch => 'hash_mismatch',
    CivitaiFailure.exists => 'exists',
    CivitaiFailure.nameTaken => 'name_taken',
    CivitaiFailure.busy => 'busy',
    CivitaiFailure.tooMany => 'too_many',
    CivitaiFailure.cancelled => 'cancelled',
    CivitaiFailure.redirect => 'redirect',
    CivitaiFailure.unsafe => 'unsafe',
    CivitaiFailure.network => 'network',
    CivitaiFailure.http => 'http',
  };

  /// One sentence for the person, never a stack or an absolute path.
  String get message => switch (kind) {
    CivitaiFailure.keyMissing =>
      'Paste an API key. CivitAI will not send the file without one.',
    CivitaiFailure.keyRefused =>
      'CivitAI refused the API key. Paste a valid key and try again.',
    CivitaiFailure.locked =>
      'CivitAI will not send this file. It may need an account with access.',
    CivitaiFailure.notFound => 'CivitAI no longer has this file.',
    CivitaiFailure.stalled =>
      'The download stalled and was stopped. Try again.',
    CivitaiFailure.short =>
      'The download ended before the whole file arrived. Try again.',
    CivitaiFailure.sizeMismatch =>
      'The file CivitAI sent is not the size it listed, so it was discarded.',
    CivitaiFailure.tooLarge => 'This file is larger than the download limit.',
    CivitaiFailure.diskFull =>
      'There is not enough free disk space for this file.',
    CivitaiFailure.hashMismatch =>
      "The file did not match CivitAI's checksum, so it was deleted.",
    CivitaiFailure.exists => 'That file is already in your models folder.',
    CivitaiFailure.nameTaken =>
      'A different file with that name is already in your models folder. '
          'Rename or remove it, then download again.',
    CivitaiFailure.busy => 'That file is already downloading.',
    CivitaiFailure.tooMany =>
      'Too many downloads are running. Wait for one to finish.',
    CivitaiFailure.cancelled => 'Download cancelled.',
    CivitaiFailure.redirect =>
      'CivitAI sent the download somewhere it is not allowed to go.',
    CivitaiFailure.unsafe =>
      detail.isEmpty ? "That file can't be saved." : detail,
    CivitaiFailure.network => 'Could not reach CivitAI.',
    CivitaiFailure.http =>
      detail.isEmpty ? 'CivitAI could not send the file.' : detail,
  };

  @override
  String toString() => 'CivitaiDownloadException($code)';
}

/// Stops one download. Cancelling twice is harmless.
class CivitaiCancel {
  bool _cancelled = false;
  final List<void Function()> _listeners = [];

  bool get isCancelled => _cancelled;

  void onCancel(void Function() listener) {
    if (_cancelled) {
      listener();
      return;
    }
    _listeners.add(listener);
  }

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    final pending = List<void Function()>.of(_listeners);
    _listeners.clear();
    for (final listener in pending) {
      listener();
    }
  }
}
