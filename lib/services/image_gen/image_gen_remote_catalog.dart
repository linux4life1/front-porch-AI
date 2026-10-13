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

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'package:front_porch_ai/services/image/image.dart';

import 'package:front_porch_ai/services/storage/settings/remote_api_key_vault.dart';

import 'nano_image_models.dart';

/// Remote model catalog for `ImageGenService.fetchImageModels`. The Nano
/// snapshot in [kCommonImageModels] is the offline fallback when GET
/// `{apiUrl}/image-models` fails.
Future<List<ImageModelInfo>> fetchNanoImageModels(
  String apiUrl,
  String apiKey,
) {
  final proUrl = nanoProImageModelsUrl(apiUrl);
  return loadNanoImageCatalog(
    fetchBody: () => _readCatalogBody('$apiUrl/image-models', apiKey),
    fallback: List<ImageModelInfo>.from(kCommonImageModels),
    fetchProBody: proUrl == null
        ? null
        : () => _readCatalogBody(proUrl, apiKey),
  );
}

/// Nano's Pro-included list lives beside the API root
/// (`/api/subscription/v1/image-models`). Other hosts have none.
String? nanoProImageModelsUrl(String apiUrl) {
  final uri = Uri.tryParse(normalizeRemoteApiUrl(apiUrl));
  if (uri == null || uri.host != 'nano-gpt.com') return null;
  if (!uri.path.endsWith('/api/v1')) return null;
  final root = uri.path.substring(0, uri.path.length - '/api/v1'.length);
  return uri.replace(path: '$root/api/subscription/v1/image-models').toString();
}

Future<String?> _readCatalogBody(String url, String apiKey) async {
  final client = http.Client();
  try {
    final response = await client
        .get(Uri.parse(url), headers: {'Authorization': 'Bearer $apiKey'})
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) return null;
    return response.body;
  } finally {
    client.close();
  }
}

/// xAI's image models. The live list is read when xAI answers it; the
/// bundled id keeps Grok Imagine usable when it does not.
Future<List<ImageModelInfo>> fetchXaiImageModels(
  String apiUrl,
  String apiKey,
) async {
  try {
    final raw = await _readCatalogBody(
      '$apiUrl/image-generation-models',
      apiKey,
    );
    final listed = raw == null
        ? const <ImageModelInfo>[]
        : parseXaiImageModels(raw);
    if (listed.isNotEmpty) return listed;
  } catch (e) {
    debugPrint('ImageGen: xAI image model list unreadable: $e');
  }
  return List<ImageModelInfo>.from(kXaiImageModels);
}

/// Fetch image models specifically from OpenRouter's API.
///
/// OpenRouter supports querying for image-capable models via:
/// GET /models?output_modalities=image
///
/// Returns the models as provided by OpenRouter with their pricing,
/// or an empty list if the API call fails.
Future<List<ImageModelInfo>> fetchOpenRouterImageModels(
  String apiUrl,
  String apiKey,
) async {
  final apiModels = <ImageModelInfo>[];
  final client = http.Client();

  try {
    // Query for models that can output images
    final uri = Uri.parse('$apiUrl/models?output_modalities=image');
    final response = await client
        .get(uri, headers: {'Authorization': 'Bearer $apiKey'})
        .timeout(const Duration(seconds: 15));

    if (response.statusCode == 200) {
      final body = jsonDecode(response.body);
      final data = body['data'] as List<dynamic>? ?? [];

      for (final m in data) {
        final id = m['id']?.toString() ?? '';
        if (id.isEmpty) continue;
        final name = m['name']?.toString() ?? id;
        final arch = m['architecture'];
        final inputs = arch is Map && arch['input_modalities'] is List
            ? arch['input_modalities'] as List
            : const [];

        // Extract pricing info if available (display as-is from OpenRouter)
        final pricing = m['pricing'] as Map<String, dynamic>?;
        String? pricingInfo;

        // NOTE: OpenRouter returns $0/$0 for free-tier-only models or unclear pricing
        // We do NOT mark these as "free" since they may have restrictions or credits only
        // Instead, we show the pricing as-is and let user check OpenRouter's site for details
        bool isPaid =
            true; // Conservative: assume paid unless clearly free ($0 everywhere)

        if (pricing != null) {
          final prompt = pricing['prompt'];
          final completion = pricing['completion'];

          // Format pricing for display (show as-is from API)
          if (prompt != null || completion != null) {
            pricingInfo = '\$$prompt / \$$completion';
          }
        }

        apiModels.add(
          ImageModelInfo(
            id: id,
            name: name,
            isPaid: isPaid,
            pricingInfo: pricingInfo,
            canEdit: inputs.contains('image'),
          ),
        );
      }

      debugPrint(
        'ImageGen: Fetched ${apiModels.length} image models from OpenRouter',
      );
    } else {
      debugPrint(
        'ImageGen: OpenRouter /models?output_modalities=image returned ${response.statusCode}',
      );
    }
  } catch (e) {
    debugPrint('ImageGen: Failed to fetch OpenRouter image models: $e');
  } finally {
    client.close();
  }

  // Sort by name for consistent display
  apiModels.sort((a, b) => a.displayName.compareTo(b.displayName));
  return apiModels;
}
