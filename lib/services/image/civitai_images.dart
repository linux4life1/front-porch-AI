// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:front_porch_ai/services/image/civitai_version.dart';

/// The one host a listing's pictures may load from on the phone.
const String kCivitaiImageHost = 'image.civitai.com';

/// [url] when it is an https picture on [kCivitaiImageHost], else null.
String? civitaiPhoneImage(String? url) {
  final uri = url == null ? null : Uri.tryParse(url);
  if (uri == null || uri.scheme != 'https') return null;
  return uri.host == kCivitaiImageHost ? url : null;
}

/// True when a listing's picture is rated X or above. A model that is fine to
/// list can still carry one, and it is not shown unless adult results are on.
bool civitaiImageIsAdult(Map image) {
  final level = image['nsfwLevel'];
  if (level is num && (level.toInt() & kCivitaiImageAdultMask) != 0) {
    return true;
  }
  final legacy = image['nsfw'];
  if (legacy is bool) return legacy;
  return legacy is String && {'mature', 'x'}.contains(legacy.toLowerCase());
}
