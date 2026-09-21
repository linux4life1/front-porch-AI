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

import 'package:front_porch_ai/services/capability/image_reference_role.dart';
import 'package:front_porch_ai/services/image/image_gen_types.dart';
import 'package:front_porch_ai/services/storage/settings/image_gen_settings.dart';
import 'package:front_porch_ai/services/storage/settings/remote_api_key_vault.dart';

/// Image Studio's two remote image hosts. Keys live in [RemoteApiKeyVault];
/// the selected URL is Image Studio–scoped and must not rewrite chat's mouth.
const kImageStudioRemoteHosts = <ImageStudioRemoteHost>[
  ImageStudioRemoteHost(id: 'nano', label: 'Nano-GPT', url: kNanoGptApiV1),
  ImageStudioRemoteHost(
    id: 'openrouter',
    label: 'OpenRouter',
    url: kOpenRouterApiV1,
  ),
];

class ImageStudioRemoteHost {
  const ImageStudioRemoteHost({
    required this.id,
    required this.label,
    required this.url,
  });

  final String id;
  final String label;
  final String url;
}

/// Image Studio fetch/generate host. A stored Studio URL wins; otherwise the
/// chat mouth is the unread first-run fallback so existing installs keep
/// working. Callers must not write the fallback back onto chat settings.
({String url, String key}) resolveImageStudioRemoteAccount({
  required String imageRemoteApiUrl,
  required String chatRemoteApiUrl,
  required String Function(String url) keyFor,
}) {
  final url = imageRemoteApiUrl.trim().isNotEmpty
      ? imageRemoteApiUrl.trim()
      : chatRemoteApiUrl.trim();
  return (url: url, key: keyFor(url));
}

String? imageRemoteHostIdFor(String url) {
  final slot = normalizeRemoteApiUrl(url);
  for (final h in kImageStudioRemoteHosts) {
    if (normalizeRemoteApiUrl(h.url) == slot) return h.id;
  }
  return null;
}

String? imageRemoteUrlForHostId(String id) {
  for (final h in kImageStudioRemoteHosts) {
    if (h.id == id) return h.url;
  }
  return null;
}

/// Nano Pro-included vs pay-per-prompt; OpenRouter keeps [pricingInfo].
String imageModelListLabel(ImageModelInfo m) {
  if (m.pricingInfo != null && m.pricingInfo!.isNotEmpty) {
    return '${m.displayName} — ${m.pricingInfo}';
  }
  return m.isPaid ? '${m.displayName} · paid' : '${m.displayName} · Pro';
}

bool imageModelMatchesQuery(ImageModelInfo m, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  return m.displayName.toLowerCase().contains(q) ||
      m.id.toLowerCase().contains(q) ||
      imageModelListLabel(m).toLowerCase().contains(q);
}

List<ImageModelInfo> filterImageModels(
  Iterable<ImageModelInfo> models,
  String query,
) => [
  for (final m in models)
    if (imageModelMatchesQuery(m, query)) m,
];

int compareImageModelsForPicker(ImageModelInfo a, ImageModelInfo b) {
  if (a.isPaid != b.isPaid) return a.isPaid ? 1 : -1;
  return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
}

/// Shown when a leftover Comfy/A1111 filename would have been POSTed to
/// Nano/OpenRouter. Pack slots should surface this — never silent-retry.
const kRemoteLocalCheckpointMessage =
    'Pick a Remote API image model. A local checkpoint '
    '(.ckpt / .safetensors) cannot be sent to Nano-GPT or OpenRouter.';

/// Remote Nano/OpenRouter image POST patience. Matches A1111's model-load
/// ceiling — Nano gens often exceed 2 minutes. Catalog (15s) and URL
/// downloads (30s) stay short; only `/images/generations`, `/images/edits`,
/// and OpenRouter `/chat/completions` image POSTs use this.
const kRemoteImageHttpTimeout = Duration(seconds: 600);

/// User-facing copy when a remote image POST hits [kRemoteImageHttpTimeout].
String formatRemoteImageTimeoutMessage([
  Duration timeout = kRemoteImageHttpTimeout,
]) {
  final minutes = timeout.inMinutes;
  return 'Remote image timed out after ${minutes}m — '
      'try again or a faster model';
}

/// First non-empty candidate that is a remote API id (and in [catalogIds]
/// when that set is provided). Local filenames never win.
String? pickRemoteImageModelId({
  String? explicit,
  required String slotModel,
  required String hostModel,
  Iterable<String>? catalogIds,
}) {
  final catalog = catalogIds == null
      ? null
      : {
          for (final id in catalogIds)
            if (id.trim().isNotEmpty) id,
        };
  bool ok(String id) {
    final trimmed = id.trim();
    if (trimmed.isEmpty || looksLikeLocalImageModel(trimmed)) return false;
    if (catalog != null && catalog.isNotEmpty && !catalog.contains(trimmed)) {
      return false;
    }
    return true;
  }

  for (final id in [explicit ?? '', hostModel, slotModel]) {
    if (ok(id)) return id.trim();
  }
  return null;
}

/// Drop a leftover local filename from the Create or Edit slot / per-host
/// map. Restores a valid per-host API id when one exists.
Future<String?> sanitizeRemoteImageSlot({
  required ImageGenSettings image,
  required String hostUrl,
  required bool editScoped,
  Iterable<String>? catalogIds,
}) async {
  final slot = editScoped ? image.imageGenEditModel : image.imageGenModel;
  final host = image.remoteImageModelFor(hostUrl, edit: editScoped);
  final picked = pickRemoteImageModelId(
    slotModel: slot,
    hostModel: host,
    catalogIds: catalogIds,
  );
  if (picked != null) {
    if (editScoped && slot != picked) {
      await image.setImageGenEditModel(picked);
    } else if (!editScoped && slot != picked) {
      await image.setImageGenModel(picked);
    }
    if (host != picked) {
      await image.setRemoteImageModelFor(hostUrl, picked, edit: editScoped);
    }
    return picked;
  }
  final catalogReject =
      catalogIds != null &&
      catalogIds.isNotEmpty &&
      slot.isNotEmpty &&
      !catalogIds.contains(slot);
  if (looksLikeLocalImageModel(slot) || catalogReject) {
    if (editScoped) {
      await image.setImageGenEditModel('');
    } else {
      await image.setImageGenModel('');
    }
  }
  return null;
}

/// Switch Studio's remote host and restore that host's last image model.
/// Writes only [ImageGenSettings] — chat [remoteApiUrl] is untouched.
/// Local checkpoint filenames are never written into [image_remote_models].
Future<void> applyImageRemoteHost({
  required ImageGenSettings image,
  required String url,
  required String chatRemoteApiUrl,
  required bool editScoped,
}) async {
  final next = normalizeRemoteApiUrl(url);
  if (next.isEmpty) return;
  final prev = normalizeRemoteApiUrl(
    image.imageRemoteApiUrl.isNotEmpty
        ? image.imageRemoteApiUrl
        : chatRemoteApiUrl,
  );
  final currentModel = editScoped
      ? image.imageGenEditModel
      : image.imageGenModel;
  if (prev.isNotEmpty &&
      currentModel.isNotEmpty &&
      prev != next &&
      !looksLikeLocalImageModel(currentModel)) {
    await image.setRemoteImageModelFor(prev, currentModel, edit: editScoped);
  }
  await image.setImageRemoteApiUrl(next);
  final restored = image.remoteImageModelFor(next, edit: editScoped);
  if (restored.isNotEmpty) {
    if (editScoped) {
      await image.setImageGenEditModel(restored);
    } else {
      await image.setImageGenModel(restored);
    }
    return;
  }
  if (looksLikeLocalImageModel(currentModel)) {
    if (editScoped) {
      await image.setImageGenEditModel('');
    } else {
      await image.setImageGenModel('');
    }
  }
}
