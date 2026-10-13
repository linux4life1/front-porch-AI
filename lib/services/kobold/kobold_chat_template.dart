// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'kobold.dart';

const kChatTemplateMaxBytes = 64 * 1024;

String kcppsChatTemplatePath(Map<String, dynamic> config) =>
    config['jinjatemplate'] is String ? config['jinjatemplate'] as String : '';

/// The preset's template as a full path: an imported one is stored relative
/// to [engineDir].
String kcppsChatTemplateFile(Map<String, dynamic> config, String engineDir) =>
    kcppsPathIn(kcppsChatTemplatePath(config), engineDir);

/// Settings the chat template field manages, so not "unmanaged" extras.
bool kcppsIsTemplateKey(String key) => key == 'jinjatemplate' || key == 'jinja';

Map<String, dynamic> kcppsWithChatTemplate(
  Map<String, dynamic> config,
  String template,
) {
  final updated = Map<String, dynamic>.of(config)..remove('jinjatemplate');
  if (template.isNotEmpty) {
    updated['jinjatemplate'] = template;
    updated['jinja'] = true;
  }
  return updated;
}

/// The web can edit only ordinary preset files in the host's engine folder.
Future<bool> canEditKoboldTemplate(String engineDir, String preset) async {
  final absolute = p.normalize(p.absolute(preset));
  return p.equals(p.dirname(absolute), p.normalize(p.absolute(engineDir))) &&
      p.extension(preset).toLowerCase() == '.kcpps' &&
      !isAppOwnedKcpps(preset) &&
      await FileSystemEntity.type(preset, followLinks: false) ==
          FileSystemEntityType.file;
}

/// Preserves every unrelated preset field. Null content clears the override.
Future<void> saveUploadedKoboldTemplate({
  required String engineDir,
  required String preset,
  String? name,
  String? content,
  bool Function()? stillSelected,
}) async {
  if (!await canEditKoboldTemplate(engineDir, preset)) {
    throw const FormatException(
      'Select a preset in the host engine folder first.',
    );
  }
  final read = await KcppsLibrary.open(preset);
  if (read.read is! KcppsOk) {
    throw const FormatException('The preset could not be read.');
  }
  String template = '';
  if (content != null) {
    template = await copyKoboldChatTemplate(
      engineDir: engineDir,
      name: name,
      content: content,
    );
  }
  if (stillSelected?.call() == false) {
    throw const FormatException('The selected preset changed. Try again.');
  }
  // Re-read after the upload so a simultaneous unrelated edit is retained.
  final latest = await KcppsLibrary.open(preset);
  if (latest.read is! KcppsOk) {
    throw const FormatException('The preset could not be read.');
  }
  await stageKoboldConfig(
    engineDir,
    p.basename(preset),
    encodeKcpps(kcppsWithChatTemplate((latest.read as KcppsOk).raw, template)),
  );
}

Future<String> copyKoboldChatTemplate({
  required String engineDir,
  required String? name,
  required String content,
}) async {
  final bytes = utf8.encode(content);
  if (name == null ||
      p.extension(name).toLowerCase() != '.jinja' ||
      bytes.isEmpty ||
      bytes.length > kChatTemplateMaxBytes ||
      content.contains('\u0000')) {
    throw const FormatException(
      'Choose a nonempty .jinja text file up to 64 KiB.',
    );
  }
  final uploadName = p.basename(name);
  if (RegExp(r'[\\/:*?"<>|\x00-\x1F]').hasMatch(uploadName)) {
    throw const FormatException(
      'The template filename contains unsupported characters.',
    );
  }
  final folder = Directory(p.join(engineDir, 'chat_templates'));
  if (await FileSystemEntity.type(folder.path, followLinks: false) ==
      FileSystemEntityType.link) {
    throw const FormatException(
      'The template folder cannot be a symbolic link.',
    );
  }
  await folder.create(recursive: true);
  final contentFolder = Directory(
    p.join(folder.path, '${sha256.convert(bytes)}'),
  );
  if (await FileSystemEntity.type(contentFolder.path, followLinks: false) ==
      FileSystemEntityType.link) {
    throw const FormatException(
      'The template folder cannot be a symbolic link.',
    );
  }
  await contentFolder.create(recursive: true);
  final template = p.join(contentFolder.path, uploadName);
  if (await FileSystemEntity.type(template, followLinks: false) ==
      FileSystemEntityType.link) {
    throw const FormatException('The template file cannot be a symbolic link.');
  }
  await File(template).writeAsBytes(bytes, flush: true);
  // Relative to the engine folder, so moving the app's data keeps it working.
  return p.relative(template, from: engineDir);
}
