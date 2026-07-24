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

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:front_porch_ai/services/voice_manager.dart';
import 'package:front_porch_ai/services/tts_service.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Dialog for browsing, downloading, and managing Piper TTS voice models.
class VoiceBrowserDialog extends StatefulWidget {
  const VoiceBrowserDialog({super.key});

  @override
  State<VoiceBrowserDialog> createState() => _VoiceBrowserDialogState();
}

class _VoiceBrowserDialogState extends State<VoiceBrowserDialog> {
  String _searchQuery = '';
  String _selectedLanguage = 'All';
  String _selectedQuality = 'All';
  Set<String> _installedVoices = {};
  bool _initialLoaded = false;

  @override
  void initState() {
    super.initState();
    // fetchCatalog notifies its listeners immediately; deferred past the
    // first frame so the notify never lands mid-build (field-reported
    // "setState() or markNeedsBuild() called during build" crash).
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  Future<void> _loadData() async {
    final voiceManager = Provider.of<VoiceManager>(context, listen: false);
    if (voiceManager.catalog.isEmpty) {
      await voiceManager.fetchCatalog();
    }
    final installed = await voiceManager.listInstalledVoices();
    if (mounted) {
      setState(() {
        _installedVoices = installed.toSet();
        _initialLoaded = true;
      });
    }
  }

  String _genderLabel(String gender) {
    switch (gender) {
      case 'Male':
        return '♂ Male';
      case 'Female':
        return '♀ Female';
      default:
        return '⚬ Unknown';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1F2937),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 900,
        height: 700,
        child: Column(
          children: [
            _buildHeader(),
            _buildFilters(),
            const Divider(height: 1, color: Colors.white10),
            Expanded(child: _buildVoiceList()),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.white10)),
      ),
      child: Row(
        children: [
          const Icon(Icons.record_voice_over, color: AppColors.formMasterAccent),
          const SizedBox(width: 12),
          const Text(
            'Voice Model Browser',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white54),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    return Consumer<VoiceManager>(
      builder: (context, vm, _) {
        // Collect unique languages and qualities
        final languages = <String>{'All'};
        final qualities = <String>{'All'};
        for (final v in vm.catalog) {
          languages.add(v.languageEnglish);
          qualities.add(v.quality);
        }
        final langList = languages.toList()..sort();
        final qualList = ['All', 'x_low', 'low', 'medium', 'high'];

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: Row(
            children: [
              // Search
              Expanded(
                flex: 3,
                child: TextField(
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Search voices...',
                    hintStyle: const TextStyle(color: Colors.white30),
                    prefixIcon: const Icon(Icons.search, color: Colors.white30),
                    filled: true,
                    fillColor: Colors.black26,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                  onChanged: (val) =>
                      setState(() => _searchQuery = val.toLowerCase()),
                ),
              ),
              const SizedBox(width: 12),
              // Language filter
              Expanded(
                flex: 2,
                child: DropdownButtonFormField<String>(
                  initialValue: _selectedLanguage,
                  dropdownColor: const Color(0xFF374151),
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Language',
                    labelStyle: const TextStyle(
                      color: Colors.white54,
                      fontSize: 12,
                    ),
                    filled: true,
                    fillColor: Colors.black26,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                  items: langList
                      .map(
                        (l) => DropdownMenuItem(
                          value: l,
                          child: Text(l, overflow: TextOverflow.ellipsis),
                        ),
                      )
                      .toList(),
                  onChanged: (val) =>
                      setState(() => _selectedLanguage = val ?? 'All'),
                ),
              ),
              const SizedBox(width: 12),
              // Quality filter
              SizedBox(
                width: 120,
                child: DropdownButtonFormField<String>(
                  initialValue: _selectedQuality,
                  dropdownColor: const Color(0xFF374151),
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Quality',
                    labelStyle: const TextStyle(
                      color: Colors.white54,
                      fontSize: 12,
                    ),
                    filled: true,
                    fillColor: Colors.black26,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                  items: qualList
                      .map((q) => DropdownMenuItem(value: q, child: Text(q)))
                      .toList(),
                  onChanged: (val) =>
                      setState(() => _selectedQuality = val ?? 'All'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildVoiceList() {
    return Consumer<VoiceManager>(
      builder: (context, vm, _) {
        if (vm.isLoadingCatalog) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text(
                  'Loading voice catalog...',
                  style: TextStyle(color: Colors.white54),
                ),
              ],
            ),
          );
        }

        if (vm.catalog.isEmpty && _initialLoaded) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off, size: 48, color: Colors.white24),
                const SizedBox(height: 12),
                const Text(
                  'Could not load voice catalog',
                  style: TextStyle(color: Colors.white54),
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: () => vm.fetchCatalog(),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ],
            ),
          );
        }

        // Filter catalog
        var filtered = vm.catalog.where((v) {
          if (_selectedLanguage != 'All' &&
              v.languageEnglish != _selectedLanguage) {
            return false;
          }
          if (_selectedQuality != 'All' && v.quality != _selectedQuality) {
            return false;
          }
          if (_searchQuery.isNotEmpty) {
            final searchable =
                '${v.name} ${v.languageEnglish} ${v.countryEnglish} ${v.key}'
                    .toLowerCase();
            if (!searchable.contains(_searchQuery)) return false;
          }
          return true;
        }).toList();

        // Sort: installed first, then by language, then by name
        filtered.sort((a, b) {
          final aInstalled = _installedVoices.contains(a.key);
          final bInstalled = _installedVoices.contains(b.key);
          if (aInstalled != bInstalled) return aInstalled ? -1 : 1;
          final langCompare = a.languageEnglish.compareTo(b.languageEnglish);
          if (langCompare != 0) return langCompare;
          return a.name.compareTo(b.name);
        });

        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          itemCount: filtered.length,
          itemBuilder: (context, index) {
            final voice = filtered[index];
            final isInstalled = _installedVoices.contains(voice.key);
            final isDownloading = vm.isDownloading(voice.key);
            final progress = vm.getDownloadProgress(voice.key);

            return Card(
              color: isInstalled
                  ? const Color(0xFF1a3a2a)
                  : const Color(0xFF374151),
              margin: const EdgeInsets.only(bottom: 6),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                leading: CircleAvatar(
                  backgroundColor: isInstalled
                      ? Colors.green.withValues(alpha: 0.2)
                      : AppColors.formMasterAccent.withValues(alpha: 0.2),
                  child: Icon(
                    isInstalled ? Icons.check_circle : Icons.record_voice_over,
                    color: isInstalled
                        ? Colors.greenAccent
                        : AppColors.formMasterAccent,
                    size: 20,
                  ),
                ),
                title: Text(
                  voice.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  '${voice.languageEnglish} (${voice.countryEnglish}) • ${_genderLabel(voice.gender)} • ${voice.quality} • ${voice.sizeLabel}',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
                trailing: _buildTrailingActions(
                  voice,
                  isInstalled,
                  isDownloading,
                  progress,
                  vm,
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildTrailingActions(
    PiperVoice voice,
    bool isInstalled,
    bool isDownloading,
    double progress,
    VoiceManager vm,
  ) {
    if (isDownloading) {
      return SizedBox(
        width: 140,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Expanded(
              child: LinearProgressIndicator(
                value: progress,
                backgroundColor: Colors.white12,
                valueColor: const AlwaysStoppedAnimation(
                  AppColors.formMasterAccent,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${(progress * 100).toStringAsFixed(0)}%',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isInstalled) ...[
          // Preview button
          IconButton(
            icon: const Icon(
              Icons.play_arrow,
              color: Colors.greenAccent,
              size: 20,
            ),
            tooltip: 'Preview',
            onPressed: () {
              final tts = Provider.of<TtsService>(context, listen: false);
              final storage = Provider.of<StorageService>(
                context,
                listen: false,
              );
              // Temporarily enable TTS for preview
              final wasEnabled = storage.ttsEnabled;
              if (!wasEnabled) storage.setTtsEnabled(true);
              tts
                  .speak(
                    'Hello! This is a preview of the ${voice.name} voice.',
                    voiceKey: voice.key,
                  )
                  .then((_) {
                    if (!wasEnabled) storage.setTtsEnabled(false);
                  });
            },
          ),
          // Delete button
          IconButton(
            icon: const Icon(
              Icons.delete_outline,
              color: Colors.redAccent,
              size: 20,
            ),
            tooltip: 'Delete',
            onPressed: () async {
              await vm.deleteVoice(voice.key);
              setState(() => _installedVoices.remove(voice.key));
            },
          ),
        ] else ...[
          // Download button
          ElevatedButton.icon(
            onPressed: () async {
              final success = await vm.downloadVoice(voice.key);
              if (success && mounted) {
                setState(() => _installedVoices.add(voice.key));
              }
            },
            icon: const Icon(Icons.download, size: 16),
            label: const Text('Download'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.formMasterAccent,
              foregroundColor: AppColors.onChaosAccent,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              textStyle: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ],
    );
  }
}
