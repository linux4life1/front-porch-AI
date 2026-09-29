// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';

import 'package:front_porch_ai/services/image/civitai_credentials.dart';

/// The API key box of the CivitAI sheet. The key lives in the OS key store.
///
/// An empty box never removes the stored key: pressing Replace and then
/// Search used to delete it. Removing is its own button, with a question.
class CivitaiKeyController extends ChangeNotifier {
  CivitaiKeyController({this.onSaveKey});

  /// Also hand a newly saved key to the caller (for a second store).
  final Future<String?> Function(String token)? onSaveKey;

  final TextEditingController field = TextEditingController();

  /// A key is stored.
  bool saved = false;

  /// The person pressed Replace or typed into the box.
  bool replacing = false;

  /// Why the saved key could not be read, while that is the case.
  String? unreadable;

  bool _disposed = false;

  /// Reads whether a key is stored. Returns the error text when it cannot.
  Future<String?> load() async {
    try {
      final store = await CivitaiCredentialStore.open();
      saved = await store.read('local') != null;
      unreadable = null;
      _tell();
      return null;
    } on CivitaiKeyStoreException catch (e) {
      unreadable = e.message;
      _tell();
      return e.message;
    }
  }

  /// Saves what was typed. Does nothing for an empty box.
  Future<String?> saveTyped() async {
    final token = field.text.trim();
    if (token.isEmpty) return null;
    try {
      final store = await CivitaiCredentialStore.open();
      await store.save('local', token);
    } on CivitaiKeyStoreException catch (e) {
      return e.message;
    }
    saved = true;
    replacing = false;
    if (!_disposed) field.clear();
    _tell();
    return onSaveKey?.call(token);
  }

  /// Removes the stored key. Returns the error text when it cannot.
  Future<String?> remove() async {
    try {
      final store = await CivitaiCredentialStore.open();
      await store.signOut('local');
    } on CivitaiKeyStoreException catch (e) {
      return e.message;
    }
    saved = false;
    replacing = false;
    _tell();
    return null;
  }

  /// A typed key is kept when the sheet closes without Save. Writes the
  /// store only; the sheet is going away.
  Future<void> keepTypedOnClose() async {
    final token = field.text.trim();
    if (token.isEmpty) return;
    try {
      final store = await CivitaiCredentialStore.open();
      await store.save('local', token);
    } on CivitaiKeyStoreException catch (e) {
      debugPrint('civitai key was not kept on close: ${e.message}');
    }
  }

  void startReplacing() {
    replacing = true;
    _tell();
  }

  void _tell() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    field.dispose();
    super.dispose();
  }
}

class CivitaiKeyPanel extends StatelessWidget {
  const CivitaiKeyPanel({
    super.key,
    required this.controller,
    required this.onMessage,
  });

  final CivitaiKeyController controller;

  /// Where a save or remove error is shown; null clears it.
  final ValueChanged<String?> onMessage;

  Future<void> _save() async => onMessage(await controller.saveTyped());

  Future<void> _remove(BuildContext context) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove the CivitAI key?'),
        content: const Text(
          'Searching adult models and downloading will ask for a key again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep it'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove key'),
          ),
        ],
      ),
    );
    if (sure != true) return;
    onMessage(await controller.remove());
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final showSaved =
            controller.saved &&
            !controller.replacing &&
            controller.field.text.isEmpty;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (controller.unreadable != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  controller.unreadable!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (showSaved) ...[
              const ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('API key saved'),
                subtitle: Text(
                  'This key is used for search and for adult results on civitai.red.',
                ),
              ),
              Row(
                children: [
                  TextButton(
                    onPressed: controller.startReplacing,
                    child: const Text('Replace'),
                  ),
                  TextButton(
                    onPressed: () => _remove(context),
                    child: const Text('Remove key'),
                  ),
                ],
              ),
            ] else
              TextField(
                controller: controller.field,
                obscureText: true,
                enableSuggestions: false,
                autocorrect: false,
                decoration: const InputDecoration(labelText: 'API key'),
                onChanged: (_) => controller.startReplacing(),
                onSubmitted: (_) => _save(),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: _save,
                child: const Text('Save key'),
              ),
            ),
          ],
        );
      },
    );
  }
}
