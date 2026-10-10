// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

part of 'image_batch_service.dart';

extension _ImageBatchStore on ImageBatchService {
  Directory get _folder => Directory(p.join(storage.rootPath!, 'ImageBatches'));

  String? _rootMoveBlocker() =>
      !_loaded || running || working || _pendingWrites > 0
      ? 'Finish the current image batch operation before moving the data directory.'
      : null;

  void _requireRootStable() {
    if (storage.rootRelocation.isMoving) {
      throw StateError('Wait for the data directory move to finish.');
    }
  }

  void _rootChanged() {
    if (!_loaded || _storedRoot == storage.rootPath) return;
    for (final job in _jobs) {
      final config = job.data['config'] as Map<String, dynamic>;
      if (config['root'] == _storedRoot) config['root'] = storage.rootPath;
    }
    _storedRoot = storage.rootPath;
    _changed();
  }

  File _file(String name) {
    if (!RegExp(r'^[a-f0-9-]+\.png$').hasMatch(name)) {
      throw FormatException('Invalid batch image name');
    }
    return File(p.join(_folder.path, name));
  }

  Future<void> _load() async {
    await storage.initialized;
    await storage.rootRelocation.settled;
    _storedRoot = storage.rootPath;
    await _folder.create(recursive: true);
    final manifest = File(p.join(_folder.path, 'queue.json'));
    if (!await manifest.exists()) {
      _loaded = true;
      return;
    }
    final data =
        jsonDecode(await manifest.readAsString()) as Map<String, dynamic>;
    if (data['version'] != 1) {
      throw StateError('Unsupported image batch format.');
    }
    for (final value in data['jobs'] as List) {
      final job = ImageBatchJob(Map<String, dynamic>.from(value as Map));
      if (job.state == 'running') {
        job.data.addAll({
          'state': 'interrupted',
          'error':
              'The app closed during this request. Check the backend before preparing another pass.',
        });
      }
      final config = job.data['config'] as Map<String, dynamic>;
      final origin = data['root'] ?? config['root'];
      if (config['root'] == origin) config['root'] = storage.rootPath;
      _jobs.add(job);
    }
    _loaded = true;
    _changed();
  }

  Future<void> _persist() {
    final content = jsonEncode({
      'version': 1,
      'root': storage.rootPath,
      'jobs': [for (final j in _jobs) j.data],
    });
    _pendingWrites++;
    final next = _writes.then((_) async {
      final temp = File(p.join(_folder.path, 'queue.json.tmp'));
      await temp.writeAsString(content, flush: true);
      await temp.rename(p.join(_folder.path, 'queue.json'));
    });
    _writes = next.then<void>(
      (_) {},
      onError: (Object e) {
        error = 'Could not save the image queue: $e';
        pauseRequested = true;
        _changed();
      },
    );
    _changed();
    return next.whenComplete(() => _pendingWrites--);
  }
}
