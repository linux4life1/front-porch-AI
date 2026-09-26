// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

/// Comfy's proxyWidgets lists the promoted internal widgets in UI order.
int comfySubgraphWidgetIndex(
  Map raw,
  List widgetPorts,
  Object? port,
  String internalNodeId,
  String inputName,
) {
  final properties = raw['properties'];
  final proxy = properties is Map ? properties['proxyWidgets'] : null;
  if (proxy is List) {
    return proxy.indexWhere(
      (entry) =>
          entry is List &&
          entry.length >= 2 &&
          entry[0].toString() == internalNodeId &&
          entry[1].toString() == inputName,
    );
  }
  return widgetPorts.indexOf(port);
}

bool isComfyPromptInput(String type, String name) =>
    (name == 'text' || name == 'prompt') &&
    (type.startsWith('CLIPTextEncode') ||
        type.startsWith('TextEncodeQwen') ||
        type == 'TextGenerate');
