// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'civitai_client.dart';
import 'civitai_errors.dart';
import 'civitai_fetch.dart';

enum CivitaiJobState { running, done, failed, cancelled }

/// One download the phone started. The request that started it returns at
/// once; the phone asks how far along it is and can stop it.
class CivitaiJob {
  CivitaiJob({required this.id, required this.account, required this.name})
    : cancel = CivitaiCancel();

  final String id;
  final String account;

  /// The file's name only. The folder it lands in never leaves the desktop.
  final String name;
  final CivitaiCancel cancel;

  CivitaiJobState state = CivitaiJobState.running;
  int received = 0;
  int? total;
  CivitaiFailure? failure;
  DateTime? finishedAt;

  int? get percent {
    final t = total;
    if (t == null || t <= 0) return null;
    return (received * 100 ~/ t).clamp(0, 100);
  }

  Map<String, Object?> toJson() {
    final kind = failure;
    return {
      'jobId': id,
      'name': name,
      'state': state.name,
      'received': received,
      'total': total,
      'percent': percent,
      if (kind != null) 'code': CivitaiDownloadException(kind).code,
      if (kind != null) 'error': CivitaiDownloadException(kind).message,
    };
  }
}

typedef CivitaiRunner =
    Future<String> Function(
      CivitaiDownloadPlan plan, {
      void Function(int received, int? total)? onProgress,
      CivitaiCancel? cancel,
      VoidCallback? onStarted,
    });

Future<String> _realRunner(
  CivitaiDownloadPlan plan, {
  void Function(int received, int? total)? onProgress,
  CivitaiCancel? cancel,
  VoidCallback? onStarted,
}) {
  return downloadCivitaiPlan(
    plan,
    onProgress: onProgress,
    cancel: cancel,
    onStarted: onStarted,
  );
}

/// Downloads started from the phone, kept for a while after they end so the
/// phone can read the result.
class CivitaiDownloads {
  CivitaiDownloads({
    CivitaiRunner? run,
    this.keepFinished = const Duration(minutes: 10),
    this.maxKept = 50,
    Random? random,
  }) : _run = run ?? _realRunner,
       _random = random ?? Random.secure();

  final CivitaiRunner _run;
  final Duration keepFinished;
  final int maxKept;
  final Random _random;
  final Map<String, CivitaiJob> _jobs = {};

  String _newId() {
    final bytes = List<int>.generate(12, (_) => _random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Starts [plan] and returns once it is underway. Throws the
  /// [CivitaiDownloadException] when it was refused before any request:
  /// already there, already running, too many, no room.
  Future<CivitaiJob> start(String account, CivitaiDownloadPlan plan) {
    _purge();
    final job = CivitaiJob(
      id: _newId(),
      account: account,
      name: p.basename(plan.path ?? ''),
    );
    final ready = Completer<CivitaiJob>();
    _jobs[job.id] = job;
    unawaited(
      _run(
        plan,
        cancel: job.cancel,
        onProgress: (received, total) {
          job.received = received;
          job.total = total;
        },
        onStarted: () {
          if (!ready.isCompleted) ready.complete(job);
        },
      ).then(
        (_) {
          job.state = CivitaiJobState.done;
          job.finishedAt = DateTime.now();
        },
        onError: (Object error) {
          final kind = error is CivitaiDownloadException
              ? error.kind
              : CivitaiFailure.network;
          job.failure = kind;
          job.state = kind == CivitaiFailure.cancelled
              ? CivitaiJobState.cancelled
              : CivitaiJobState.failed;
          job.finishedAt = DateTime.now();
          if (!ready.isCompleted) {
            _jobs.remove(job.id);
            ready.completeError(error);
          }
        },
      ),
    );
    return ready.future;
  }

  /// The job, only for the account that started it.
  CivitaiJob? job(String id, String account) {
    _purge();
    final found = _jobs[id];
    if (found == null || found.account != account) return null;
    return found;
  }

  /// Stops a running job. False when there is no such job for [account].
  bool cancel(String id, String account) {
    final found = job(id, account);
    if (found == null) return false;
    if (found.state == CivitaiJobState.running) found.cancel.cancel();
    return true;
  }

  void _purge() {
    final now = DateTime.now();
    _jobs.removeWhere((_, job) {
      final done = job.finishedAt;
      return done != null && now.difference(done) > keepFinished;
    });
    while (_jobs.length > maxKept) {
      final finished = _jobs.entries
          .where((e) => e.value.finishedAt != null)
          .map((e) => e.key);
      if (finished.isEmpty) break;
      _jobs.remove(finished.first);
    }
  }
}
