// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

/// How a generation leaves the app. Draw Things is gRPC on 7859, never the
/// Automatic1111 HTTP path. The app does not start ComfyUI.
String? studioTransport(String backend, {int drawThingsPort = 7859}) {
  switch (backend) {
    case 'drawthings':
      return 'grpc:$drawThingsPort';
    case 'a1111':
      return 'http:a1111';
    case 'comfyui':
      return 'http:comfy';
    case 'remote':
      return 'http:remote';
    default:
      return null;
  }
}


