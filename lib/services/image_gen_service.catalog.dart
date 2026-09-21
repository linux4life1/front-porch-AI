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

part of 'image_gen_service.dart';

/// Cluster C — remote model catalog. fetchImageModels() itself (fake-pinned)
/// stays a shell instance member; this extension holds only the OpenRouter
/// HTTP helper it delegates to. The Nano image snapshot is
/// `_commonImageModels` in `image_gen_service.nano_models.dart`.
extension _ImageGenCatalog on ImageGenService {
  /// Fetch image models specifically from OpenRouter's API.
  ///
  /// OpenRouter supports querying for image-capable models via:
  /// GET /models?output_modalities=image
  ///
  /// Returns the models as provided by OpenRouter with their pricing,
  /// or an empty list if the API call fails.
  Future<List<ImageModelInfo>> _fetchOpenRouterImageModels(
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
}
