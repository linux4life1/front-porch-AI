// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

class ImageBatchJob {
  ImageBatchJob(this.data);
  final Map<String, dynamic> data;
  String get id => data['id'] as String;
  String get characterId => data['characterId'] as String;
  String get characterName => data['characterName'] as String;
  String get kind => data['kind'] as String;
  String get label => data['label'] as String;
  String get prompt => data['prompt'] as String;
  String get state => data['state'] as String;
  bool get edit => data['edit'] == true;
  bool get kept => data['kept'] == true;
  Map<String, dynamic> view() => Map.of(data);
}
