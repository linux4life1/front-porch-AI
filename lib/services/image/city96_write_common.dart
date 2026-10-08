// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:math';

/// The update was not written, and why. The message is shown as it is.
class City96WriteRefused implements Exception {
  const City96WriteRefused(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 128 random bits as hex, for a temp file name nobody can guess.
String city96Token() {
  final random = Random.secure();
  return List.generate(
    16,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}
