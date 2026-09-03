// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

import 'package:shelf/shelf.dart' as shelf;

import 'package:front_porch_ai/services/web/auth/auth_service.dart';
import 'package:front_porch_ai/services/web/util/client_ip.dart';
import 'package:front_porch_ai/services/web/util/json_response.dart';

/// True when [body] would persist a new remote API URL or overwrite the key.
///
/// An unchanged URL (the Settings page always re-sends the current value) and
/// a blank `apiKey` (leave-unchanged) do not need a password step-up.
bool remoteCredentialWriteNeedsStepUp(
  Map<String, dynamic> body, {
  required String currentRemoteApiUrl,
}) {
  if (body.containsKey('remoteApiUrl') &&
      body['remoteApiUrl'].toString() != currentRemoteApiUrl) {
    return true;
  }
  final apiKey = body['apiKey']?.toString();
  return apiKey != null && apiKey.isNotEmpty;
}

/// True when POST /api/image/config would persist a new remote URL/key **or**
/// a new local image-gen host (A1111 / Comfy / Draw Things). A stolen
/// session cookie must not redirect generation at any of those.
bool imageConfigWriteNeedsStepUp(
  Map<String, dynamic> body, {
  required String currentRemoteApiUrl,
  required String currentLocalUrl,
  required String currentComfyUrl,
  required String currentDrawThingsHost,
}) {
  if (remoteCredentialWriteNeedsStepUp(
    body,
    currentRemoteApiUrl: currentRemoteApiUrl,
  )) {
    return true;
  }
  if (body['localUrl'] is String &&
      body['localUrl'].toString() != currentLocalUrl) {
    return true;
  }
  if (body['comfyUrl'] is String &&
      body['comfyUrl'].toString() != currentComfyUrl) {
    return true;
  }
  if (body['drawThingsHost'] is String &&
      body['drawThingsHost'].toString() != currentDrawThingsHost) {
    return true;
  }
  return false;
}

/// True when a preview call (`apiUrl` / `apiKey`) would use a host or key
/// other than the already-saved remote credentials.
///
/// Empty / omitted fields fall back to the stored pair and stay session-only.
/// A caller-supplied host with the stored key is the leftover the persist
/// gate does not cover — that must step up too.
bool remoteCredentialPreviewNeedsStepUp(
  Map<String, dynamic> body, {
  required String currentRemoteApiUrl,
  required String currentRemoteApiKey,
}) {
  final previewUrl = body['apiUrl']?.toString();
  if (previewUrl != null &&
      previewUrl.trim().isNotEmpty &&
      previewUrl.trim() != currentRemoteApiUrl.trim()) {
    return true;
  }
  final previewKey = body['apiKey']?.toString();
  if (previewKey != null && previewKey.isNotEmpty) {
    return previewKey != currentRemoteApiKey;
  }
  return false;
}

/// Null when re-auth passed; otherwise the HTTP error to return unchanged.
Future<shelf.Response?> denyUnlessSteppedUp({
  required AuthService auth,
  required Map<String, dynamic> body,
  required shelf.Request request,
}) async {
  final status = await auth.verifyStepUp(
    currentPassword: body['currentPassword']?.toString() ?? '',
    totpCode: body['totpCode']?.toString(),
    ip: requestClientIp(request),
  );
  if (status == CredentialChangeStatus.success) return null;
  return stepUpError(status);
}

/// Map a failed [CredentialChangeStatus] to the HTTP body the PWA already
/// handles for tunnel enable / credential change.
shelf.Response stepUpError(CredentialChangeStatus status) {
  switch (status) {
    case CredentialChangeStatus.invalidCurrentPassword:
      return JsonResponse.unauthorized('Current password is incorrect');
    case CredentialChangeStatus.totpRequired:
      return JsonResponse.error(
        401,
        'Two-factor code required',
        extra: const {'totpRequired': true},
      );
    case CredentialChangeStatus.lockedOut:
      return JsonResponse.tooManyRequests('Too many attempts, try again later');
    case CredentialChangeStatus.notSetUp:
      return JsonResponse.error(409, 'Account not configured');
    case CredentialChangeStatus.alreadyEnabled:
    case CredentialChangeStatus.invalidInput:
    case CredentialChangeStatus.success:
      return JsonResponse.unauthorized('Re-authentication required');
  }
}
