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

import 'dart:convert';

/// Canonical slot for a remote OpenAI-compatible endpoint.
///
/// Host is case-insensitive; a trailing slash is ignored so the OpenRouter
/// and Nano-GPT preset chips and a typed `…/v1/` land in the same bucket.
String normalizeRemoteApiUrl(String url) {
  final trimmed = url.trim();
  if (trimmed.isEmpty) return '';
  final uri = Uri.tryParse(trimmed);
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
    return trimmed.replaceFirst(RegExp(r'/+$'), '');
  }
  final path = uri.path.replaceFirst(RegExp(r'/+$'), '');
  return Uri(
    scheme: uri.scheme.toLowerCase(),
    host: uri.host.toLowerCase(),
    port: uri.hasPort ? uri.port : null,
    path: path,
  ).toString();
}

/// Per-URL API keys for OpenRouter / Nano-GPT / custom hosts.
///
/// The live `remote_api_key` pref is the key for the *active* URL. This vault
/// remembers the others so a preset switch restores the right key (or empty)
/// instead of carrying the previous host's key into Check Connection.
class RemoteApiKeyVault {
  RemoteApiKeyVault([Map<String, String>? initial])
    : _keys = {
        for (final e in (initial ?? {}).entries)
          if (normalizeRemoteApiUrl(e.key).isNotEmpty &&
              e.value.trim().isNotEmpty)
            normalizeRemoteApiUrl(e.key): e.value.trim(),
      };

  final Map<String, String> _keys;

  String keyFor(String url) {
    final slot = normalizeRemoteApiUrl(url);
    if (slot.isEmpty) return '';
    return _keys[slot] ?? '';
  }

  void put(String url, String key) {
    final slot = normalizeRemoteApiUrl(url);
    if (slot.isEmpty) return;
    final trimmed = key.trim();
    if (trimmed.isEmpty) {
      _keys.remove(slot);
    } else {
      _keys[slot] = trimmed;
    }
  }

  List<String> get urlsWithKeys => List<String>.unmodifiable(_keys.keys);

  String encode() => jsonEncode(_keys);

  static RemoteApiKeyVault decode(String? raw) {
    if (raw == null || raw.isEmpty) return RemoteApiKeyVault();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return RemoteApiKeyVault();
      return RemoteApiKeyVault({
        for (final e in decoded.entries) e.key.toString(): e.value.toString(),
      });
    } catch (_) {
      return RemoteApiKeyVault();
    }
  }
}

/// Chip URLs. A leftover `sk-or-` key with no host of record lands here,
/// not on whichever URL happened to be selected when the shared pref froze.
const kOpenRouterApiV1 = 'https://openrouter.ai/api/v1';
const kNanoGptApiV1 = 'https://nano-gpt.com/api/v1';

bool remoteApiUrlIsOpenRouter(String url) {
  final host = Uri.tryParse(normalizeRemoteApiUrl(url))?.host ?? '';
  return host == 'openrouter.ai' || host.endsWith('.openrouter.ai');
}

bool remoteApiUrlIsNanoGpt(String url) {
  final host = Uri.tryParse(normalizeRemoteApiUrl(url))?.host ?? '';
  return host == 'nano-gpt.com' || host.endsWith('.nano-gpt.com');
}

bool remoteApiKeyLooksOpenRouter(String key) =>
    key.trim().toLowerCase().startsWith('sk-or-');

bool remoteApiKeyLooksNanoGpt(String key) =>
    key.trim().toLowerCase().startsWith('sk-nano-');

/// Canonical home for a leftover shared key, or null when the shape is unknown.
String? canonicalHomeUrlForRemoteApiKey(String key) {
  if (remoteApiKeyLooksOpenRouter(key)) {
    return normalizeRemoteApiUrl(kOpenRouterApiV1);
  }
  if (remoteApiKeyLooksNanoGpt(key)) {
    return normalizeRemoteApiUrl(kNanoGptApiV1);
  }
  return null;
}

/// True when [key] may be stored under [url]. Unknown shapes belong to the
/// caller's URL (custom hosts). `sk-or-` never belongs on Nano-GPT.
bool remoteApiKeyBelongsToUrl(String key, String url) {
  if (key.trim().isEmpty) return false;
  if (remoteApiKeyLooksOpenRouter(key)) return remoteApiUrlIsOpenRouter(url);
  if (remoteApiKeyLooksNanoGpt(key)) return remoteApiUrlIsNanoGpt(url);
  return true;
}

/// Attribute a pre-vault shared `remote_api_key` without writing a foreign
/// leftover into [activeUrl]. Mutates [vault]. Returns the active key to keep
/// (empty when the leftover belongs to another host and that slot is empty).
String applyLegacySharedRemoteApiKey({
  required RemoteApiKeyVault vault,
  required String activeUrl,
  required String sharedKey,
}) {
  final key = sharedKey.trim();
  if (key.isEmpty) return vault.keyFor(activeUrl);

  if (remoteApiKeyBelongsToUrl(key, activeUrl)) {
    vault.put(activeUrl, key);
    return key;
  }

  final home = canonicalHomeUrlForRemoteApiKey(key);
  if (home != null && vault.keyFor(home).isEmpty) {
    vault.put(home, key);
  }
  return vault.keyFor(activeUrl);
}
