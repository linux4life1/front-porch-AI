// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

/// Additive hub check: `gold` (owner) / `blue` (trusted uploader).
/// Missing, empty, or any other value is no badge — older servers omit it.
String? stoopVerificationOf(Object? raw) {
  if (raw == 'gold' || raw == 'blue') return raw as String;
  return null;
}

/// A signed-in account on the Front Porch repository server.
///
/// This is the public projection returned by the backend (`/auth/me`,
/// `/auth/login`, `/auth/signup`) — never includes secrets.
class BackporchUser {
  final String id;
  final String email;
  final String displayName;

  /// Hub verification badge: `gold`, `blue`, or null (none / older server).
  final String? verification;

  /// One of `USER`, `MOD`, `OWNER`. Regular repo users are always `USER`.
  final String role;

  /// Whether the 18+ age gate has been completed for this account.
  final bool ageVerified;

  /// Whether the account's email address is confirmed. Sharing requires it;
  /// browsing and downloading never do. Defaults true so an older server that
  /// doesn't report the field can't make the app nag about a gate it lacks.
  final bool emailVerified;

  /// Whether the user has opted into seeing NSFW content (policy default: off).
  final bool nsfwEnabled;

  /// The AUP version this account last agreed to, or null if never. Compared
  /// against the live `policyVersion` to decide whether to (re-)show the gate.
  final String? acceptedPolicyVersion;

  /// Whether the account has an authenticator (TOTP) second factor enabled.
  /// Optional for everyone — users can turn it on/off from the account sheet.
  final bool twoFactorEnabled;

  /// Public creator-profile fields (shown on the profile tab + creator page).
  /// All optional/additive — an older server simply never sends them.
  final String bio;
  final List<String> profileLinks;

  /// The current profile picture's asset id (`/assets/{id}/raw`), or null for
  /// the amber monogram. A new upload always arrives under a NEW id.
  final String? avatarAssetId;

  /// True when a moderator revoked this account's avatar privilege.
  final bool avatarLocked;

  /// When the account was created ("On the porch since …"). Null on servers
  /// that predate the field.
  final DateTime? createdAt;

  /// An email change awaiting its confirmation click at the NEW address, or
  /// null. The account keeps [email] until that link is opened.
  final String? pendingEmail;

  /// Whether the server actually sent `emailVerified`. Older servers omit it
  /// and [emailVerified] defaults true so Report still works. Comments are
  /// fail-closed: omitted is NOT verified (see stoopCanComment).
  final bool emailVerifiedKnown;

  const BackporchUser({
    required this.id,
    required this.email,
    required this.displayName,
    this.verification,
    required this.role,
    required this.ageVerified,
    this.emailVerified = true,
    this.emailVerifiedKnown = true,
    required this.nsfwEnabled,
    required this.acceptedPolicyVersion,
    required this.twoFactorEnabled,
    this.bio = '',
    this.profileLinks = const [],
    this.avatarAssetId,
    this.avatarLocked = false,
    this.createdAt,
    this.pendingEmail,
  });

  bool get isModerator => role == 'MOD' || role == 'OWNER';

  factory BackporchUser.fromJson(Map<String, dynamic> json) => BackporchUser(
    id: json['id'] as String? ?? '',
    email: json['email'] as String? ?? '',
    displayName: json['displayName'] as String? ?? '',
    verification: stoopVerificationOf(json['verification']),
    role: json['role'] as String? ?? 'USER',
    ageVerified: json['ageVerified'] as bool? ?? false,
    emailVerified: json['emailVerified'] as bool? ?? true,
    emailVerifiedKnown: json.containsKey('emailVerified'),
    nsfwEnabled: json['nsfwEnabled'] as bool? ?? false,
    acceptedPolicyVersion: json['acceptedPolicyVersion'] as String?,
    twoFactorEnabled: json['twoFactorEnabled'] as bool? ?? false,
    bio: json['bio'] as String? ?? '',
    profileLinks: ((json['profileLinks'] as List?) ?? const [])
        .whereType<String>()
        .toList(),
    avatarAssetId: json['avatarAssetId'] as String?,
    avatarLocked: json['avatarLocked'] as bool? ?? false,
    // `is String` (not a cast): a malformed field must cost one line on the
    // profile, never the whole /auth/me parse.
    createdAt: json['createdAt'] is String
        ? DateTime.tryParse(json['createdAt'] as String)
        : null,
    pendingEmail: json['pendingEmail'] as String?,
  );
}
