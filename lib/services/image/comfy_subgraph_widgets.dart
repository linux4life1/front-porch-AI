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

Object? subgraphWidgetValue(Map raw, String? portName, int index) {
  final named = raw['widgets_values_named'];
  if (named is Map && named.containsKey(portName)) return named[portName];
  final widgets = raw['widgets_values'];
  return widgets is List && index >= 0 && index < widgets.length
      ? widgets[index]
      : null;
}

bool isComfyPromptInput(String type, String name) =>
    (name == 'text' || name == 'prompt') &&
    (type.startsWith('CLIPTextEncode') ||
        type.startsWith('TextEncodeQwen') ||
        type == 'TextGenerate');

bool isExposedPromptFeed(String? port, String type, String name) =>
    (port == 'prompt' || port == 'text') &&
    (isComfyPromptInput(type, name) ||
        (type == 'ComfySwitchNode' &&
            (name == 'on_false' || name == 'on_true')));
