// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

/// A signed-in account on the Front Porch repository server.
///
/// This is the public projection returned by the backend (`/auth/me`,
/// `/auth/login`, `/auth/signup`) — never includes secrets.
class BackporchUser {
  final String id;
  final String email;
  final String displayName;

  /// One of `USER`, `MOD`, `OWNER`. Regular repo users are always `USER`.
  final String role;

  /// Whether the 18+ age gate has been completed for this account.
  final bool ageVerified;

  /// Whether the user has opted into seeing NSFW content (policy default: off).
  final bool nsfwEnabled;

  /// The AUP version this account last agreed to, or null if never. Compared
  /// against the live `policyVersion` to decide whether to (re-)show the gate.
  final String? acceptedPolicyVersion;

  /// Whether the account has an authenticator (TOTP) second factor enabled.
  /// Optional for everyone — users can turn it on/off from the account sheet.
  final bool twoFactorEnabled;

  const BackporchUser({
    required this.id,
    required this.email,
    required this.displayName,
    required this.role,
    required this.ageVerified,
    required this.nsfwEnabled,
    required this.acceptedPolicyVersion,
    required this.twoFactorEnabled,
  });

  bool get isModerator => role == 'MOD' || role == 'OWNER';

  factory BackporchUser.fromJson(Map<String, dynamic> json) => BackporchUser(
    id: json['id'] as String? ?? '',
    email: json['email'] as String? ?? '',
    displayName: json['displayName'] as String? ?? '',
    role: json['role'] as String? ?? 'USER',
    ageVerified: json['ageVerified'] as bool? ?? false,
    nsfwEnabled: json['nsfwEnabled'] as bool? ?? false,
    acceptedPolicyVersion: json['acceptedPolicyVersion'] as String?,
    twoFactorEnabled: json['twoFactorEnabled'] as bool? ?? false,
  );
}
