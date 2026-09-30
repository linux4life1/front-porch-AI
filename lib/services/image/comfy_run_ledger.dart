// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// A ComfyUI run that was stopped on purpose.
class ComfyRunCancelled implements Exception {
  const ComfyRunCancelled();

  @override
  String toString() => 'Cancelled.';
}

/// The prompts one ComfyUI client has in flight, so stopping a run stops the
/// job on the server too (not only the wait for it).
///
/// A prompt that is still queued is removed from the queue; one that is
/// running is interrupted, and only when the queue says it is ours, so
/// another job on the same server is never interrupted by mistake.
class ComfyRunLedger {
  final Set<String> _running = {};
  final Set<String> _cancelled = {};
  int _submitting = 0;
  bool _stopWhenSubmitted = false;
  bool _stopNext = false;

  /// A workflow is about to be posted.
  void submitting() {
    _submitting++;
    if (_stopNext) _stopWhenSubmitted = true;
  }

  /// A new generation begins: an earlier cancel does not reach it.
  void clearStop() => _stopNext = false;

  /// Whether the next post is to be stopped as soon as it has a name.
  bool get stopIsPending => _stopNext;

  /// The post finished ([id] is null when it failed). A stop asked for while
  /// it was in flight is carried out now that the prompt has a name.
  Future<void> submitted(String root, String? id) async {
    _submitting--;
    if (id == null) return;
    _running.add(id);
    if (_stopWhenSubmitted) {
      _stopWhenSubmitted = _submitting > 0;
      _cancelled.add(id);
      await _stop(root, id);
    }
  }

  bool isCancelled(String id) => _cancelled.contains(id);

  void finished(String id) {
    _running.remove(id);
    _cancelled.remove(id);
  }

  /// Stops every prompt this client has posted and not seen finish. With
  /// [beforePost], a generation is under way that has not posted yet (it is
  /// still fetching lists or uploading the picture): what it posts is stopped
  /// as soon as it has a name.
  Future<void> cancel(String root, {bool beforePost = false}) async {
    if (beforePost) _stopNext = true;
    if (_submitting > 0) _stopWhenSubmitted = true;
    final ids = _running.toList();
    _cancelled.addAll(ids);
    for (final id in ids) {
      await _stop(root, id);
    }
  }

  /// Takes [id] off the queue, and interrupts only when the queue says it is
  /// the one running. An older ComfyUI ignores the prompt_id and stops
  /// whatever is running, so an interrupt sent on a guess (the queue could not
  /// be read) could stop someone else's job.
  Future<void> _stop(String root, String id) async {
    const wait = Duration(seconds: 5);
    const json = {'Content-Type': 'application/json'};
    try {
      var running = await _isRunning(root, id);
      await http
          .post(
            Uri.parse('$root/queue'),
            headers: json,
            body: jsonEncode({
              'delete': [id],
            }),
          )
          .timeout(wait);
      // It may have started between the look and the delete.
      running = running == true || await _isRunning(root, id) == true;
      if (running) {
        await http
            .post(
              Uri.parse('$root/interrupt'),
              headers: json,
              body: jsonEncode({'prompt_id': id}),
            )
            .timeout(wait);
      }
    } catch (e) {
      debugPrint('ComfyUI: could not stop $id: $e');
    }
  }

  /// Whether the queue lists [id] as running; null when it cannot be told.
  Future<bool?> _isRunning(String root, String id) async {
    try {
      final r = await http
          .get(Uri.parse('$root/queue'))
          .timeout(const Duration(seconds: 5));
      if (r.statusCode != 200) return null;
      final running = (jsonDecode(r.body) as Map)['queue_running'];
      if (running is! List) return null;
      return running.any((entry) => entry is List && entry.contains(id));
    } catch (_) {
      return null;
    }
  }
}
