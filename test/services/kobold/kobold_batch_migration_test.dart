// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Auto mode picks the batch for the machine, now the default. Someone who
// chose a batch before Auto existed keeps theirs (the migration table:
// "Context size, batch size: unchanged").

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/storage/settings/backend_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<BackendSettings> _open(Map<String, Object> stored) async {
  final probe = BackendSettings();
  SharedPreferences.setMockInitialValues({
    for (final e in stored.entries) probe.k(e.key): e.value,
  });
  final settings = BackendSettings()
    ..initializeBase(await SharedPreferences.getInstance(), () {});
  return settings..load();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a fresh install is on Auto', () async {
    expect((await _open({})).batchAutomatic, isTrue);
  });

  test('a batch chosen before Auto existed is kept', () async {
    final s = await _open({'blas_batch_size': 4096});
    expect(s.batchAutomatic, isFalse);
    expect(s.blasBatchSize, 4096);
  });

  test('once chosen, Auto or a number stays chosen', () async {
    expect(
      (await _open({
        'blas_batch_size': 4096,
        'kobold_batch_automatic': true,
      })).batchAutomatic,
      isTrue,
    );
    expect(
      (await _open({'kobold_batch_automatic': false})).batchAutomatic,
      isFalse,
    );
  });
}
