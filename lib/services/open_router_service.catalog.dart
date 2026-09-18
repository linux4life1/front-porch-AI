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

part of 'open_router_service.dart';

/// Model catalog fetch. Overrides never touch live configure() state.
extension OpenRouterServiceCatalog on OpenRouterService {
  /// Fetch the list of available models with pricing info from the API.
  /// Lists models from [apiUrl] (else this service's live URL). Pass the
  /// target EXPLICITLY when fetching for a picker: this service is the ONE
  /// shared client for Remote API and oMLX, and UI sites that called
  /// `configure(...)` just to point a list-fetch somewhere were silently
  /// re-routing the ACTIVE backend's chat traffic (opening Settings while on
  /// oMLX sent every request to the Remote API provider until the next
  /// storage sync). The overrides fetch without touching live state.
  Future<List<RemoteModelInfo>> _fetchAvailableModels({
    String? apiUrl,
    String? apiKey,
  }) async {
    final url = apiUrl ?? _apiUrl;
    final key = apiKey ?? _apiKey;
    if (url.isEmpty) return [];
    final isLocal = url.contains('localhost') || url.contains('127.0.0.1');
    if (key.isEmpty && !isLocal) return [];

    // Same seam as [refreshReachability]: tests inject a MockClient so
    // this never hits the network (flutter test HttpOverrides is a
    // bodiless 400, which used to empty the picker and flip isReady).
    final client = httpClientFactory?.call() ?? http.Client();
    final owned = httpClientFactory == null;
    var batched = false;
    try {
      final uri = Uri.parse('$url/models');
      debugPrint('[OpenRouter] Fetching models from: $uri');
      final response = await client
          .get(uri, headers: remoteAuthHeaders(key))
          .timeout(const Duration(seconds: 15));

      debugPrint('[OpenRouter] Response status: ${response.statusCode}');
      if (response.statusCode != 200) {
        debugPrint('[OpenRouter] Error body: ${response.body}');
        return [];
      }

      final body = jsonDecode(response.body);
      debugPrint('[OpenRouter] Response keys: ${body.keys.toList()}');
      // Handle both OpenAI format ('data') and LM Studio format ('models')
      final data =
          (body['data'] as List<dynamic>?) ??
          (body['models'] as List<dynamic>?) ??
          [];
      debugPrint('[OpenRouter] Found ${data.length} model entries');
      if (data.isNotEmpty) {
        debugPrint('[OpenRouter] First entry type: ${data.first.runtimeType}');
        debugPrint('[OpenRouter] First entry: ${data.first}');
      }
      beginReasoningEffortCatalogBatch();
      batched = true;
      final models = <RemoteModelInfo>[];

      for (final m in data) {
        String id = '';
        String name = '';

        if (m is String) {
          // Plain string list of model names (some backends)
          id = m;
          name = m;
        } else if (m is Map) {
          id =
              m['id']?.toString() ??
              m['key']?.toString() ??
              m['name']?.toString() ??
              m['model']?.toString() ??
              '';
          name =
              m['display_name']?.toString() ??
              m['name']?.toString() ??
              m['id']?.toString() ??
              id;
        }
        if (id.isEmpty) continue;
        if (m is Map) {
          rememberReasoningProfileFromCatalog(id, m['reasoning']);
          if (isOpenRouterApiUrl(url)) {
            final advertised = toolsAdvertisedFromParameters(
              m['supported_parameters'],
            );
            if (advertised != null) {
              OpenRouterToolSupport.instance.rememberFromCatalog(
                id,
                advertised: advertised,
              );
            }
          }
        }
        // `m` is dynamic, so indexing a plain-String entry dispatches to
        // String.operator[](int) and THROWS — which aborted the whole loop and
        // emptied the picker for any backend answering {"models":["llama-3"]},
        // the very shape the `m is String` branch above exists to support.
        final pricing = m is Map ? m['pricing'] : null;

        // API returns USD per token; convert to per 1M tokens for readability
        double? promptCost;
        double? completionCost;
        if (pricing is Map) {
          final promptRaw = double.tryParse(
            pricing['prompt']?.toString() ?? '',
          );
          final completionRaw = double.tryParse(
            pricing['completion']?.toString() ?? '',
          );
          if (promptRaw != null) promptCost = promptRaw * 1000000;
          if (completionRaw != null) completionCost = completionRaw * 1000000;
        }

        models.add(
          RemoteModelInfo(
            id: id,
            name: name,
            promptCostPerMillion: promptCost,
            completionCostPerMillion: completionCost,
          ),
        );
      }

      debugPrint('[OpenRouter] Parsed ${models.length} models');
      models.sort((a, b) => a.id.compareTo(b.id));
      return models;
    } catch (e) {
      debugPrint('[OpenRouter] Error fetching models: $e');
      return [];
    } finally {
      if (batched) endReasoningEffortCatalogBatch();
      if (owned) client.close();
    }
  }
}
