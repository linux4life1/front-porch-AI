// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

/// A ComfyUI rejection the stove can show. [message] is the detail, capped.
class ImageSubmitError {
  final String url;
  final String? nodeId;
  final String? nodeClass;
  final String message;

  const ImageSubmitError({
    required this.url,
    required this.message,
    this.nodeId,
    this.nodeClass,
  });

  /// Banner text. The node is included when Comfy named one.
  String get banner {
    final where = nodeId == null
        ? ''
        : ' node $nodeId${nodeClass == null ? '' : ' ($nodeClass)'}';
    return 'ComfyUI at $url rejected$where. $message';
  }
}

/// Caps [raw] at 240 characters without splitting a surrogate pair.
String capDetail(String raw) {
  final trimmed = raw.trim();
  if (trimmed.length <= 240) return trimmed;
  var end = 240;
  final units = trimmed.codeUnits;
  if (end > 0 && end < units.length) {
    final at = units[end - 1];
    final next = units[end];
    if (at >= 0xD800 && at <= 0xDBFF && next >= 0xDC00 && next <= 0xDFFF) {
      end -= 1;
    }
  }
  return trimmed.substring(0, end);
}

String _nodeReason(Object? node) {
  if (node is! Map) return '';
  final errors = node['errors'];
  if (errors is! List || errors.isEmpty) return '';
  final first = errors.first;
  if (first is! Map) return '';
  final details = first['details']?.toString() ?? '';
  if (details.trim().isNotEmpty) return details;
  return first['message']?.toString() ?? '';
}

/// `POST /prompt` failure body. Prefers the named node's own error.
ImageSubmitError? parseComfySubmitFailure(String url, String body) {
  Object? decoded;
  try {
    decoded = jsonDecode(body);
  } catch (_) {
    final text = capDetail(body);
    if (text.isEmpty) return null;
    return ImageSubmitError(url: url, message: text);
  }
  if (decoded is! Map) {
    return ImageSubmitError(url: url, message: capDetail(body));
  }
  String? nodeId;
  String? nodeClass;
  var nodeReason = '';
  final nodeErrors = decoded['node_errors'];
  if (nodeErrors is Map && nodeErrors.isNotEmpty) {
    final first = nodeErrors.entries.first;
    nodeId = first.key.toString();
    final value = first.value;
    if (value is Map) {
      nodeClass = value['class_type']?.toString();
      nodeReason = _nodeReason(value);
    }
  }
  var message = nodeReason;
  if (message.trim().isEmpty) {
    final error = decoded['error'];
    if (error is String) {
      message = error;
    } else if (error is Map) {
      final details = error['details']?.toString() ?? '';
      final top = error['message']?.toString() ?? '';
      message = details.trim().isNotEmpty ? details : top;
    }
  }
  final hasPrompt = decoded['prompt_id'] != null;
  final errorsEmpty = nodeErrors is! Map || nodeErrors.isEmpty;
  if (hasPrompt && errorsEmpty && message.trim().isEmpty) return null;
  if (message.trim().isEmpty && nodeId == null) {
    return ImageSubmitError(url: url, message: capDetail(body));
  }
  return ImageSubmitError(
    url: url,
    nodeId: nodeId,
    nodeClass: nodeClass,
    message: capDetail(
      message.isEmpty ? 'Prompt outputs failed validation' : message,
    ),
  );
}

/// History `status.messages` entries shaped
/// `["execution_error", {node_id, node_type, exception_message}]`.
ImageSubmitError? parseComfyHistoryError(String url, Object? statusMessages) {
  if (statusMessages is! List) return null;
  for (final item in statusMessages) {
    if (item is! List || item.length < 2) continue;
    if (item[0] != 'execution_error') continue;
    final payload = item[1];
    if (payload is! Map) continue;
    var message = payload['exception_message']?.toString() ?? '';
    if (message.trim().isEmpty) {
      message = payload['exception_type']?.toString() ?? '';
    }
    return ImageSubmitError(
      url: url,
      nodeId: payload['node_id']?.toString(),
      nodeClass: payload['node_type']?.toString(),
      message: capDetail(message),
    );
  }
  return null;
}
