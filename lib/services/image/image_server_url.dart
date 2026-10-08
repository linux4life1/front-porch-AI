// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

String normalizeImageServerUrl(String url) {
  var value = url.trim().replaceAll(RegExp(r'/+$'), '');
  if (value.isNotEmpty && !value.contains('://')) value = 'http://$value';
  return value;
}
