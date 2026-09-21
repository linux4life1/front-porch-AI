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

/// Switch Studio's remote host and restore that host's last image model.
/// Writes only [ImageGenSettings] — chat [remoteApiUrl] is untouched.
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
  if (prev.isNotEmpty && currentModel.isNotEmpty && prev != next) {
    await image.setRemoteImageModelFor(prev, currentModel);
  }
  await image.setImageRemoteApiUrl(next);
  final restored = image.remoteImageModelFor(next);
  if (restored.isEmpty) return;
  if (editScoped) {
    await image.setImageGenEditModel(restored);
  } else {
    await image.setImageGenModel(restored);
  }
}
