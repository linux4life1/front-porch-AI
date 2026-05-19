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

import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:archive/archive_io.dart';
import 'package:front_porch_ai/database/database.dart' show AvatarImage;
import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/services/character_repository.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/utils/emotion_labels.dart';

/// Dialog for managing character expression images.
/// Glassmorphic UI matching SillyTavern expression drawer aesthetic.
class CharacterAvatarsDialog extends StatefulWidget {
  final CharacterCard character;
  final CharacterRepository repository;
  final StorageService storage;

  const CharacterAvatarsDialog({
    super.key,
    required this.character,
    required this.repository,
    required this.storage,
  });

  static Future<bool?> show({
    required BuildContext context,
    required CharacterCard character,
    required CharacterRepository repository,
    required StorageService storage,
  }) {
    return showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      builder: (_) => CharacterAvatarsDialog(
        character: character,
        repository: repository,
        storage: storage,
      ),
    ).then((value) => value ?? false);
  }

  @override
  State<CharacterAvatarsDialog> createState() => _CharacterAvatarsDialogState();
}

class _CharacterAvatarsDialogState extends State<CharacterAvatarsDialog> {
  late List<AvatarImage> _avatars;
  late int _primeIndex;
  bool _saving = false;
  final Map<String, String> _tempLabels = {};

  // Pending image upload: bytes + preview, shown inline when emotion picker is active
  Uint8List? _pendingImageBytes;
  bool _showingEmotionPicker = false;

  @override
  void initState() {
    super.initState();
    _avatars = List.from(widget.character.avatarImages ?? []);
    _primeIndex = widget.character.primeAvatarIndex;
    for (final avatar in _avatars) {
      _tempLabels[avatar.id] = avatar.label ?? '';
    }
    debugPrint('[AvatarsDialog] initState: ${_avatars.length} avatars loaded');
  }

  int get _maxAvatars => 30;
  String get _avatarDirPath => widget.storage
      .characterAvatarDir(widget.character.name)
      .path;

  /// Pick a file, then show the inline emotion picker.
  Future<void> _addAvatar() async {
    debugPrint('[AvatarsDialog] _addAvatar: called, count=${_avatars.length}, max=$_maxAvatars');
    if (_avatars.length >= _maxAvatars) {
      debugPrint('[AvatarsDialog] _addAvatar: ABORT - at max');
      return;
    }

    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );

    if (result == null) {
      debugPrint('[AvatarsDialog] _addAvatar: file picker returned null');
      return;
    }
    debugPrint('[AvatarsDialog] _addAvatar: file picker returned ${result.files.length} files');
    if (result.files.isEmpty) {
      debugPrint('[AvatarsDialog] _addAvatar: ABORT - no files');
      return;
    }

    // On macOS desktop, .bytes is often null — read from .path instead
    Uint8List bytes;
    if (result.files.first.bytes != null) {
      bytes = result.files.first.bytes!;
    } else if (result.files.first.path != null) {
      debugPrint('[AvatarsDialog] _addAvatar: bytes null, reading from path=${result.files.first.path}');
      bytes = await File(result.files.first.path!).readAsBytes();
    } else {
      debugPrint('[AvatarsDialog] _addAvatar: ABORT - both bytes and path are null');
      return;
    }
    debugPrint('[AvatarsDialog] _addAvatar: got ${bytes.length} bytes, showing emotion picker');

    if (!mounted) {
      debugPrint('[AvatarsDialog] _addAvatar: ABORT - widget not mounted');
      return;
    }

    // Store bytes and show inline emotion picker
    setState(() {
      _pendingImageBytes = bytes;
      _showingEmotionPicker = true;
    });
    debugPrint('[AvatarsDialog] _addAvatar: setState done, _showingEmotionPicker=true');
  }

  /// Called when user selects an emotion from the inline picker.
  Future<void> _confirmEmotionPick(String? emotion) async {
    debugPrint('[AvatarsDialog] _confirmEmotionPick: emotion=$emotion');
    final bytes = _pendingImageBytes;
    if (bytes == null) {
      debugPrint('[AvatarsDialog] _confirmEmotionPick: ABORT - no pending bytes');
      return;
    }

    setState(() {
      _pendingImageBytes = null;
      _showingEmotionPicker = false;
    });
    debugPrint('[AvatarsDialog] _confirmEmotionPick: calling _saveAvatarToDisk');

    await _saveAvatarToDisk(bytes, emotion);
  }

  /// Cancel the pending image upload.
  void _cancelEmotionPick() {
    debugPrint('[AvatarsDialog] _cancelEmotionPick: called');
    setState(() {
      _pendingImageBytes = null;
      _showingEmotionPicker = false;
    });
  }

  Future<void> _importSpritePack() async {
    if (_avatars.length >= _maxAvatars) return;

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
      allowMultiple: false,
    );

    if (result == null || result.files.isEmpty) return;

    // On macOS desktop, .bytes is often null — read from .path instead
    Uint8List zipBytes;
    if (result.files.first.bytes != null) {
      zipBytes = result.files.first.bytes!;
    } else if (result.files.first.path != null) {
      zipBytes = await File(result.files.first.path!).readAsBytes();
    } else {
      return;
    }

    setState(() => _saving = true);
    try {
      final avatarDir = widget.storage.characterAvatarDir(widget.character.name);
      if (!await avatarDir.exists()) {
        await avatarDir.create(recursive: true);
      }

      final zipDecoder = ZipDecoder();
      final archiveData = zipDecoder.decodeBytes(zipBytes);

      final imageExtensions = {'.png', '.jpg', '.jpeg', '.webp', '.gif'};
      int imported = 0;
      int unrecognized = 0;

      for (final entry in archiveData) {
        if (!entry.isFile) continue;

        final ext = entry.name.split('.').last.toLowerCase();
        if (!imageExtensions.contains('.$ext')) continue;

        final nameWithoutExt = entry.name.replaceAll(RegExp(r'\.\w+$'), '');
        String? emotionLabel;

        for (final label in EmotionLabels.all) {
          if (nameWithoutExt.toLowerCase() == label ||
              nameWithoutExt.toLowerCase().startsWith('$label-') ||
              nameWithoutExt.toLowerCase().startsWith('$label.') ||
              nameWithoutExt.toLowerCase().startsWith('${label}_')) {
            emotionLabel = label;
            break;
          }
        }

        if (emotionLabel == null) {
          unrecognized++;
          continue;
        }

        final Uint8List? data = entry.content as Uint8List?;
        if (data == null) continue;

        if (_avatars.length + imported >= _maxAvatars) break;

        final ts = DateTime.now().millisecondsSinceEpoch + imported;
        final filename = 'avatar_${ts}_$emotionLabel.png';
        final filePath = '${avatarDir.path}/$filename';
        await File(filePath).writeAsBytes(data);

        await widget.repository.addAvatar(
          widget.character.dbId!,
          widget.character.name,
          data,
          emotionLabel,
        );
        imported++;
      }

      _avatars = await widget.repository.getAvatarImages(
        widget.character.dbId!,
      );

      if (mounted) {
        setState(() {});
        String message = 'Imported $imported expression image(s).';
        if (unrecognized > 0) {
          message += ' $unrecognized unrecognized.';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: imported > 0 ? Colors.green : Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to import ZIP: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveAvatarToDisk(Uint8List bytes, [String? emotionLabel]) async {
    debugPrint('[AvatarsDialog] _saveAvatarToDisk: started, bytes=${bytes.length}, emotion=$emotionLabel');
    setState(() => _saving = true);
    try {
      final avatarDir = widget.storage.characterAvatarDir(widget.character.name);
      debugPrint('[AvatarsDialog] _saveAvatarToDisk: avatarDir=${avatarDir.path}');
      if (!await avatarDir.exists()) {
        debugPrint('[AvatarsDialog] _saveAvatarToDisk: creating directory');
        await avatarDir.create(recursive: true);
      }

      final labelSuffix = emotionLabel != null && emotionLabel.isNotEmpty
          ? '_$emotionLabel'
          : '';
      final filename = 'avatar_${DateTime.now().millisecondsSinceEpoch}$labelSuffix.png';
      final filePath = '${avatarDir.path}/$filename';
      debugPrint('[AvatarsDialog] _saveAvatarToDisk: writing file=$filePath');
      await File(filePath).writeAsBytes(bytes);
      debugPrint('[AvatarsDialog] _saveAvatarToDisk: file written, calling repository.addAvatar');

      await widget.repository.addAvatar(
        widget.character.dbId!,
        widget.character.name,
        bytes,
        emotionLabel,
      );
      debugPrint('[AvatarsDialog] _saveAvatarToDisk: addAvatar done, reloading');

      _avatars = await widget.repository.getAvatarImages(
        widget.character.dbId!,
      );
      debugPrint('[AvatarsDialog] _saveAvatarToDisk: reloaded ${_avatars.length} avatars');

      if (mounted) {
        setState(() {
          // Sync _tempLabels with reloaded avatars so new entries show their label
          for (final avatar in _avatars) {
            if (!_tempLabels.containsKey(avatar.id)) {
              _tempLabels[avatar.id] = avatar.label ?? '';
            }
          }
        });
        debugPrint('[AvatarsDialog] _saveAvatarToDisk: setState done, success');
      }
    } catch (e, stack) {
      debugPrint('[AvatarsDialog] _saveAvatarToDisk: ERROR: $e\n$stack');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to add avatar: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _removeAvatar(String avatarId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (_) => _GlassmorphicAlertDialog(
        title: 'Remove Avatar',
        content: 'Remove this expression image?',
        cancelLabel: 'Cancel',
        confirmLabel: 'Remove',
        confirmDanger: true,
      ),
    );

    if (confirmed != true) return;

    try {
      await widget.repository.removeAvatar(
        widget.character.dbId!,
        avatarId,
      );

      _avatars = await widget.repository.getAvatarImages(
        widget.character.dbId!,
      );

      // Adjust prime index if needed
      if (_avatars.isNotEmpty) {
        _primeIndex = _primeIndex.clamp(1, _avatars.length);
      }

      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to remove avatar: $e')),
        );
      }
    }
  }

  Future<void> _setPrime(int index) async {
    setState(() => _saving = true);
    try {
      _primeIndex = index + 1;
      await widget.repository.setPrimeAvatar(
        widget.character.dbId!,
        _primeIndex,
      );
      widget.character.primeAvatarIndex = _primeIndex;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to set prime: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _updateLabel(String avatarId, String newLabel) {
    _tempLabels[avatarId] = newLabel;
    setState(() {});
  }

  Future<void> _saveLabels() async {
    for (final avatar in _avatars) {
      final label = _tempLabels[avatar.id] ?? '';
      if (label != avatar.label) {
        await widget.repository.updateAvatarLabel(avatar.id, label);
      }
    }
  }

  Future<void> _saveAll() async {
    setState(() => _saving = true);
    try {
      await _saveLabels();
      widget.character.primeAvatarIndex = _primeIndex;
      widget.character.avatarImages = _avatars;

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    debugPrint('[AvatarsDialog] build: _showingEmotionPicker=$_showingEmotionPicker, _pendingImageBytes=${_pendingImageBytes != null ? "${_pendingImageBytes!.length} bytes" : "null"}, _avatars.length=${_avatars.length}');
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 780, maxHeight: 720),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFF1a1a3a).withValues(alpha: 0.92),
                  const Color(0xFF0f0f2a).withValues(alpha: 0.95),
                ],
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.12),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  blurRadius: 30,
                  offset: const Offset(0, 8),
                ),
                BoxShadow(
                  color: const Color(0xFF6366f1).withValues(alpha: 0.08),
                  blurRadius: 60,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Glassmorphic header
                _buildHeader(),

                // Emotion picker (inline) or avatar grid
                Flexible(
                  child: Container(
                    margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                    child: _showingEmotionPicker
                        ? _buildInlineEmotionPicker()
                        : (_avatars.isEmpty
                            ? _buildEmptyState()
                            : _buildAvatarGrid()),
                  ),
                ),

                // Bottom action bar
                _buildActionBar(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Colors.white.withValues(alpha: 0.06),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF818cf8).withValues(alpha: 0.7),
                  const Color(0xFF6366f1).withValues(alpha: 0.4),
                ],
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.mood,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          const Text(
            'Expression Images',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.08),
              ),
            ),
            child: Text(
              '${_avatars.length}/$_maxAvatars',
              style: TextStyle(
                fontSize: 12,
                color: _avatars.length >= _maxAvatars
                    ? const Color(0xFFf87171)
                    : Colors.white.withValues(alpha: 0.5),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const Spacer(),
          if (_saving)
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF818cf8)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 50),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.03),
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.06),
                width: 1,
              ),
            ),
            child: const Icon(
              Icons.image,
              size: 48,
              color: Color(0xFF6366f1),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'No expression images yet',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.white70,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Add images for different emotions to bring your character to life',
            style: TextStyle(
              fontSize: 13,
              color: Colors.white.withValues(alpha: 0.35),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatarGrid() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const BouncingScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.78,
      ),
      itemCount: _avatars.length,
      itemBuilder: (context, index) {
        final avatar = _avatars[index];
        final isPrime = avatar.displayOrder + 1 == _primeIndex;
        return _GlassmorphicAvatarCard(
          key: ValueKey(avatar.id),
          avatar: avatar,
          isPrime: isPrime,
          label: _tempLabels[avatar.id] ?? '',
          onLabelChanged: _updateLabel,
          onSetPrime: () => _setPrime(index),
          onRemove: () => _removeAvatar(avatar.id),
          avatarDirPath: _avatarDirPath,
        );
      },
    );
  }

  /// Inline emotion picker shown within the dialog (no nested overlay).
  Widget _buildInlineEmotionPicker() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Image preview
        if (_pendingImageBytes != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Container(
              height: 100,
              width: 100,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.1),
                  width: 1,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(11),
                child: Image.memory(
                  _pendingImageBytes!,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),

        // Title
        const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: Text(
            'Choose Emotion for this Image',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Colors.white70,
            ),
          ),
        ),

        // Emotion grid
        Expanded(
          child: GridView.builder(
            shrinkWrap: true,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 5,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: 2.8,
            ),
            itemCount: EmotionLabels.all.length,
            itemBuilder: (context, index) {
              final emotion = EmotionLabels.all[index];
              final emoji = EmotionLabels.emoji[emotion] ?? '';
              return _EmotionChip(
                emotion: emotion,
                emoji: emoji,
                onTap: () => _confirmEmotionPick(emotion),
              );
            },
          ),
        ),

        // Cancel button
        Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 4),
          child: TextButton(
            onPressed: _cancelEmotionPick,
            style: TextButton.styleFrom(
              foregroundColor: Colors.white.withValues(alpha: 0.4),
            ),
            child: const Text('Cancel'),
          ),
        ),
      ],
    );
  }

  Widget _buildActionBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: Colors.white.withValues(alpha: 0.06),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          // Add Image button
          _GlassButton(
            label: 'Add Image',
            icon: Icons.add_photo_alternate,
            gradient: const LinearGradient(
              colors: [Color(0xFF6366f1), Color(0xFF818cf8)],
            ),
            onPressed: _saving || _showingEmotionPicker || _avatars.length >= _maxAvatars ? null : _addAvatar,
          ),
          const SizedBox(width: 10),

          // Import ZIP button
          _GlassButton(
            label: 'Import ZIP',
            icon: Icons.folder_zip,
            gradient: const LinearGradient(
              colors: [Color(0xFFa855f7), Color(0xFFc084fc)],
            ),
            onPressed: _saving || _showingEmotionPicker || _avatars.length >= _maxAvatars ? null : _importSpritePack,
          ),
          const SizedBox(width: 10),

          const Spacer(),

          // Cancel button
          TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context, false),
            style: TextButton.styleFrom(
              foregroundColor: Colors.white.withValues(alpha: 0.5),
            ),
            child: const Text('Cancel'),
          ),
          const SizedBox(width: 8),

          // Done button
          Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF10b981), Color(0xFF34d399)],
              ),
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF10b981).withValues(alpha: 0.3),
                  blurRadius: 12,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: TextButton(
              onPressed: _saving ? null : _saveAll,
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
              ),
              child: const Text(
                'Done',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Bottom sheet for picking emotion label.
/// A single emotion chip in the picker.
class _EmotionChip extends StatelessWidget {
  final String emotion;
  final String emoji;
  final VoidCallback onTap;

  const _EmotionChip({
    required this.emotion,
    required this.emoji,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: 0.08),
                Colors.white.withValues(alpha: 0.03),
              ],
            ),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.1),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                emoji,
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(width: 5),
              Text(
                emotion,
                style: const TextStyle(
                  fontSize: 11,
                  color: Colors.white70,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Glassmorphic avatar card for the expression grid.
class _GlassmorphicAvatarCard extends StatelessWidget {
  final AvatarImage avatar;
  final bool isPrime;
  final String label;
  final void Function(String avatarId, String newLabel) onLabelChanged;
  final VoidCallback onSetPrime;
  final VoidCallback onRemove;
  final String avatarDirPath;

  const _GlassmorphicAvatarCard({
    super.key,
    required this.avatar,
    required this.isPrime,
    required this.label,
    required this.onLabelChanged,
    required this.onSetPrime,
    required this.onRemove,
    required this.avatarDirPath,
  });

  @override
  Widget build(BuildContext context) {
    // avatarDirPath already includes /avatars, so use it directly
    final avatarFile = File('$avatarDirPath/${avatar.filename}');

    return GestureDetector(
      onTap: onSetPrime,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isPrime
                ? const Color(0xFFfbbf24).withValues(alpha: 0.5)
                : Colors.white.withValues(alpha: 0.08),
            width: isPrime ? 1.5 : 1,
          ),
          boxShadow: isPrime
              ? [
                  BoxShadow(
                    color: const Color(0xFFfbbf24).withValues(alpha: 0.15),
                    blurRadius: 12,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(13),
          child: Stack(
            children: [
              // Background image
              SizedBox.expand(
                child: Image.file(
                  avatarFile,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _err, _stack) => Container(
                    color: Colors.white.withValues(alpha: 0.04),
                    child: const Icon(
                      Icons.image_not_supported,
                      size: 32,
                      color: Colors.white24,
                    ),
                  ),
                ),
              ),

              // Dark gradient overlay
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.1),
                      Colors.black.withValues(alpha: 0.75),
                    ],
                    stops: const [0.3, 0.6, 1.0],
                  ),
                ),
              ),

              // Prime star badge (top-right)
              Positioned(
                top: 5,
                right: 5,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: isPrime
                        ? const Color(0xFFfbbf24).withValues(alpha: 0.9)
                        : Colors.black.withValues(alpha: 0.45),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.2),
                      width: 0.5,
                    ),
                  ),
                  child: Icon(
                    Icons.star_rounded,
                    size: 15,
                    color: isPrime ? Colors.black87 : Colors.white60,
                  ),
                ),
              ),

              // Delete button (top-left)
              Positioned(
                top: 5,
                left: 5,
                child: GestureDetector(
                  onTap: onRemove,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.45),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.15),
                        width: 0.5,
                      ),
                    ),
                    child: const Icon(
                      Icons.close,
                      size: 14,
                      color: Color(0xFFf87171),
                    ),
                  ),
                ),
              ),

              // Emotion label badge (bottom)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  child: _buildEmotionLabel(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmotionLabel() {
    final lower = label.toLowerCase();
    final emoji = EmotionLabels.emoji[lower] ?? '';
    final isKnown = EmotionLabels.all.contains(lower);

    return DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: isKnown ? lower : null,
        hint: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (emoji.isNotEmpty) ...[
              Text(emoji, style: const TextStyle(fontSize: 10)),
              const SizedBox(width: 3),
            ],
            Flexible(
              child: Text(
                isKnown ? label : 'No emotion',
                style: TextStyle(
                  fontSize: 10,
                  color: isKnown ? const Color(0xFFc4b5fd) : Colors.white70,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Icon(Icons.arrow_drop_down, size: 14, color: Colors.white54),
          ],
        ),
        isDense: true,
        iconSize: 14,
        style: const TextStyle(fontSize: 10, color: Colors.white),
        dropdownColor: const Color(0xFF1a1a3a),
        items: EmotionLabels.all.map((emotion) {
          return DropdownMenuItem(
            value: emotion,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  EmotionLabels.emoji[emotion] ?? '',
                  style: const TextStyle(fontSize: 12),
                ),
                const SizedBox(width: 5),
                Text(
                  emotion,
                  style: const TextStyle(fontSize: 11, color: Colors.white70),
                ),
              ],
            ),
          );
        }).toList(),
        onChanged: (value) {
          if (value != null) onLabelChanged(avatar.id, value);
        },
      ),
    );
  }
}

/// Reusable glassmorphic button.
class _GlassButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Gradient gradient;
  final VoidCallback? onPressed;

  const _GlassButton({
    required this.label,
    required this.icon,
    required this.gradient,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Container(
      decoration: BoxDecoration(
        gradient: enabled ? gradient : null,
        color: enabled ? null : Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        boxShadow: enabled
            ? [
                BoxShadow(
                  color: (gradient as LinearGradient).colors.first.withValues(alpha: 0.25),
                  blurRadius: 10,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: TextButton.icon(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: enabled ? Colors.white : Colors.white24,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        ),
        icon: Icon(icon, size: 16),
        label: Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
      ),
    );
  }
}

/// Glassmorphic alert dialog for confirmations.
class _GlassmorphicAlertDialog extends StatelessWidget {
  final String title;
  final String content;
  final String cancelLabel;
  final String confirmLabel;
  final bool confirmDanger;

  const _GlassmorphicAlertDialog({
    required this.title,
    required this.content,
    required this.cancelLabel,
    required this.confirmLabel,
    this.confirmDanger = false,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: 320,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFF1e1e3e).withValues(alpha: 0.95),
                const Color(0xFF12122a).withValues(alpha: 0.97),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.1),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 20,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                content,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white54,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                      child: Text(cancelLabel),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: confirmDanger
                            ? const Color(0xFFef4444).withValues(alpha: 0.8)
                            : const Color(0xFF6366f1).withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                        child: Text(
                          confirmLabel,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}