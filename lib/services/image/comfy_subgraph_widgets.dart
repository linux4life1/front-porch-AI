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
        (type == 'StringConcatenate' &&
            (name == 'string_a' || name == 'string_b')) ||
        (type == 'ComfySwitchNode' &&
            (name == 'on_false' || name == 'on_true')));

/// Resolve a boundary port from its promoted owner before applying fanout.
Object? promotedSubgraphWidgetValue(
  Map raw,
  List widgetPorts,
  Map port,
  List<(String, String, Map<String, Object?>)> consumers,
) {
  final properties = raw['properties'];
  final proxy = properties is Map ? properties['proxyWidgets'] : null;
  final owner =
      consumers.where((consumer) {
        return proxy is List &&
            proxy.any(
              (entry) =>
                  entry is List &&
                  entry.length >= 2 &&
                  entry[0].toString() == consumer.$1 &&
                  entry[1].toString() == consumer.$2,
            );
      }).firstOrNull ??
      consumers
          .where((consumer) => consumer.$3[consumer.$2] != null)
          .firstOrNull;
  final index = comfySubgraphWidgetIndex(
    raw,
    widgetPorts,
    port,
    owner?.$1 ?? '',
    owner?.$2 ?? '',
  );
  return subgraphWidgetValue(raw, port['name']?.toString(), index) ??
      owner?.$3[owner.$2];
}
