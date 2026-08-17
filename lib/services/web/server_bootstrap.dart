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
import 'package:shelf_router/shelf_router.dart';

import 'package:front_porch_ai/services/web/middleware/auth_middleware.dart';
import 'package:front_porch_ai/services/web/middleware/cors_middleware.dart';
import 'package:front_porch_ai/services/web/middleware/gzip_middleware.dart';
import 'package:front_porch_ai/services/web/middleware/security_headers.dart';
import 'package:front_porch_ai/services/web/routes/routes.dart';
import 'package:front_porch_ai/services/web/util/util.dart';
import 'package:front_porch_ai/services/web/web_server_deps.dart';

/// The single place that assembles the request handler from [WebServerDeps].
///
/// Route groups are constructed here and never reference the host. Phase 1 wires
/// auth + static; service-facade route groups (chat/character/story/…) are added
/// to this builder in Phase 3 and the WebSocket upgrade in Phase 2.
shelf.Handler buildWebHandler(WebServerDeps deps) {
  final staticRoutes = StaticRoutes();

  // Shared avatar/card thumbnail cache — lets the library grid pull tiny
  // downscaled images instead of full-resolution card PNGs (see ThumbnailCache).
  final thumbnails = ThumbnailCache(deps.storage.webThumbnailCacheDir);

  // Unmatched routes: JSON 404 for the API surface, SPA fallback for everything
  // else (client-side routing).
  final router = Router(
    notFoundHandler: (shelf.Request request) {
      if (request.url.path.startsWith('api/')) {
        return JsonResponse.error(404, 'Not found');
      }
      return staticRoutes.handle(request);
    },
  );

  WebAuthRoutes(deps, router);
  if (deps.streamHub != null) StreamRoutes(deps, router);
  if (deps.characterFacade != null) {
    WebCharacterRoutes(
      deps.characterFacade!,
      router,
      thumbnails: thumbnails,
      authoring: deps.characterAuthoringFacade,
      library: deps.characterLibraryFacade,
    );
  }
  if (deps.chargenFacade != null) WebChargenRoutes(deps.chargenFacade!, router);
  if (deps.chatFacade != null) WebChatRoutes(deps.chatFacade!, router);
  if (deps.chatPackageFacade != null) {
    WebChatPackageRoutes(deps.chatPackageFacade!, router);
  }
  if (deps.chatToolsFacade != null) {
    WebChatToolsRoutes(deps.chatToolsFacade!, router);
  }
  if (deps.groupFacade != null) {
    WebGroupRoutes(deps.groupFacade!, router, thumbnails: thumbnails);
  }
  if (deps.settingsFacade != null) {
    WebSettingsRoutes(deps, router);
  }
  if (deps.stoopFacade != null) WebStoopRoutes(deps.stoopFacade!, router);
  if (deps.worldFacade != null) WebWorldRoutes(deps.worldFacade!, router);
  if (deps.backendFacade != null || deps.imageFacade != null) {
    WebBackendRoutes(
      deps,
      router,
      backend: deps.backendFacade,
      image: deps.imageFacade,
    );
  }
  if (deps.voiceFacade != null) WebVoiceRoutes(deps.voiceFacade!, router);
  if (deps.storyFacade != null) WebStoryRoutes(deps.storyFacade!, router);
  if (deps.storyExportFacade != null) {
    WebStoryExportRoutes(deps.storyExportFacade!, router);
  }
  if (deps.tunnelManager != null) {
    WebRemoteRoutes(deps, deps.tunnelManager!, router);
  }

  return shelf.Pipeline()
      .addMiddleware(const CorsMiddleware().middleware)
      .addMiddleware(SecurityHeaders(deps).middleware)
      .addMiddleware(WebAuthMiddleware(deps).middleware)
      // Innermost: compress the handler's response (JSON/text) before the outer
      // header middlewares annotate it. Skips WebSocket upgrades + binary.
      .addMiddleware(const GzipMiddleware().middleware)
      .addHandler(router.call);
}
