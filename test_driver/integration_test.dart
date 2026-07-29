// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Host-side driver for `flutter drive`, per the flutter-add-integration-test
// skill. Day-to-day local runs don't need it — use:
//   flutter test integration_test/app_smoke_test.dart -d macos
// It exists so CI (or profiling runs) can use the flutter drive form:
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/app_smoke_test.dart -d macos

import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver();
