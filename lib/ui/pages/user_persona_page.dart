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
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:front_porch_ai/services/user_persona_service.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/utils/persona_colors.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/dialogs/export_persona_dialog.dart';
import 'package:front_porch_ai/utils/picker_prefs.dart';

class UserPersonaPage extends StatefulWidget {
  const UserPersonaPage({super.key});

  @override
  State<UserPersonaPage> createState() => _UserPersonaPageState();
}

class _UserPersonaPageState extends State<UserPersonaPage>
    with SingleTickerProviderStateMixin {
  bool _isEditing = false;
  UserPersona? _editingPersona;

  final _formKey = GlobalKey<FormState>();
  late TextEditingController _titleController;
  late TextEditingController _nameController;
  late TextEditingController _personaController;
  String? _avatarPath;

  late AnimationController _headerAnimController;
  late Animation<double> _headerGlowAnimation;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController();
    _nameController = TextEditingController();
    _personaController = TextEditingController();

    _headerAnimController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);
    _headerGlowAnimation = Tween<double>(begin: 0.3, end: 0.7).animate(
      CurvedAnimation(parent: _headerAnimController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _nameController.dispose();
    _personaController.dispose();
    _headerAnimController.dispose();
    super.dispose();
  }

  void _startEditing(UserPersona? persona) {
    setState(() {
      _isEditing = true;
      _editingPersona = persona;
      _titleController.text = persona?.title ?? '';
      _nameController.text = persona?.name ?? '';
      _personaController.text = persona?.persona ?? '';
      _avatarPath = persona?.avatarPath;
    });
  }

  void _cancelEditing() {
    setState(() {
      _isEditing = false;
      _editingPersona = null;
      _titleController.clear();
      _nameController.clear();
      _personaController.clear();
      _avatarPath = null;
    });
  }

  Future<void> _pickAvatar() async {
    final result = await PickerPrefs.pickFiles(
      category: PickerPrefs.catImage,
      type: FileType.image,
      allowMultiple: false,
    );

    if (result != null && result.files.single.path != null) {
      setState(() {
        _avatarPath = result.files.single.path;
      });
    }
  }

  Future<void> _savePersona() async {
    if (_formKey.currentState!.validate()) {
      final service = Provider.of<UserPersonaService>(context, listen: false);
      final personaText = _personaController.text;

      if (_editingPersona != null) {
        final updated = _editingPersona!.copyWith(
          title: _titleController.text,
          name: _nameController.text,
          persona: personaText,
          avatarPath: _avatarPath,
        );
        await service.updatePersona(updated);
      } else {
        await service.createPersona(
          _titleController.text,
          _nameController.text,
          personaText,
          _avatarPath,
        );
      }

      _cancelEditing();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(
                  Icons.check_circle,
                  color: Colors.greenAccent,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(
                  'Persona saved successfully',
                  style: TextStyle(color: AppColors.textPrimary(context)),
                ),
              ],
            ),
            backgroundColor: AppColors.surfaceContainerOf(context),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _importPersona() async {
    final result = await PickerPrefs.pickFiles(
      category: PickerPrefs.catImport,
      type: FileType.custom,
      allowedExtensions: ['json'],
    );

    if (result != null && result.files.single.path != null) {
      final service = Provider.of<UserPersonaService>(context, listen: false);
      final storage = Provider.of<StorageService>(context, listen: false);
      final avatarDir = storage.rootPath != null
          ? '${storage.rootPath}/persona_avatars'
          : null;

      final imported = await service.importFromJsonFile(
        result.files.single.path!,
        avatarSaveDir: avatarDir,
      );

      if (mounted) {
        if (imported != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(
                    Icons.download_done,
                    color: Colors.greenAccent,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Imported "${imported.name}" successfully',
                    style: TextStyle(color: AppColors.textPrimary(context)),
                  ),
                ],
              ),
              backgroundColor: AppColors.surfaceContainerOf(context),
              behavior: SnackBarBehavior.floating,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(
                    Icons.error_outline,
                    color: Colors.redAccent,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Import failed — unrecognized format',
                    style: TextStyle(color: AppColors.textPrimary(context)),
                  ),
                ],
              ),
              backgroundColor: AppColors.surfaceContainerOf(context),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    }
  }

  Future<void> _exportPersona(UserPersona persona) async {
    String? outputFile = await PickerPrefs.saveFile(
      category: PickerPrefs.catExport,
      dialogTitle: 'Export Persona',
      fileName:
          '${persona.name.replaceAll(RegExp(r'[^\w\s]'), '').replaceAll(' ', '_')}_FPAIpersona.json',
      type: FileType.custom,
      allowedExtensions: ['json'],
    );

    if (outputFile != null) {
      if (!outputFile.endsWith('.json')) outputFile += '.json';
      final service = Provider.of<UserPersonaService>(context, listen: false);
      await service.exportPersonasToSTFormat([persona.id], outputFile);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Exported to $outputFile',
              style: TextStyle(color: AppColors.textPrimary(context)),
            ),
            backgroundColor: AppColors.surfaceContainerOf(context),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _showExportDialog() {
    final service = Provider.of<UserPersonaService>(context, listen: false);
    showDialog(
      context: context,
      builder: (context) => ExportPersonaDialog(personas: service.personas),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundOf(context),
      appBar: AppBar(
        title: Text(
          _isEditing
              ? (_editingPersona == null ? 'Create Persona' : 'Edit Persona')
              : 'User Personas',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: _isEditing
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: _cancelEditing,
              )
            : null,
        actions: _isEditing
            ? null
            : [
                IconButton(
                  icon: const Icon(Icons.download, color: Colors.cyanAccent),
                  tooltip: 'Import Persona (JSON)',
                  onPressed: _importPersona,
                ),
                IconButton(
                  icon: const Icon(Icons.upload, color: Colors.amberAccent),
                  tooltip: 'Export Personas (JSON)',
                  onPressed: _showExportDialog,
                ),
                const SizedBox(width: 4),
                ElevatedButton.icon(
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('New Persona'),
                  onPressed: () => _startEditing(null),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6366F1),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
              ],
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 350),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) {
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0.03, 0),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
          );
        },
        child: _isEditing
            ? _buildEditForm(context, key: const ValueKey('edit'))
            : _buildMainView(key: const ValueKey('list')),
      ),
    );
  }

  // ── Main View ──────────────────────────────────────────────────────────

  Widget _buildMainView({Key? key}) {
    return Consumer<UserPersonaService>(
      key: key,
      builder: (context, service, child) {
        if (service.personas.isEmpty) {
          return _buildEmptyState(context);
        }

        final activePersona = service.persona;
        final accentColor = PersonaColors.getColorForPersona(activePersona.id);

        return CustomScrollView(
          slivers: [
            // Hero header
            SliverToBoxAdapter(
              child: _buildHeroHeader(activePersona, accentColor, service),
            ),

            // Section label
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(28, 24, 28, 12),
                child: Row(
                  children: [
                    Container(
                      width: 3,
                      height: 18,
                      decoration: BoxDecoration(
                        color: const Color(0xFF6366F1),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'All Personas (${service.personas.length})',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary(context),
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Persona grid
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 340,
                  childAspectRatio: 1.35,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                ),
                delegate: SliverChildBuilderDelegate((context, index) {
                  final persona = service.personas[index];
                  final isActive = persona.id == activePersona.id;
                  return _buildPersonaCard(context, persona, isActive, service);
                }, childCount: service.personas.length),
              ),
            ),
          ],
        );
      },
    );
  }

  // ── Hero Header ────────────────────────────────────────────────────────

  Widget _buildHeroHeader(
    UserPersona activePersona,
    Color accentColor,
    UserPersonaService service,
  ) {
    return AnimatedBuilder(
      animation: _headerGlowAnimation,
      builder: (context, child) {
        return Container(
          margin: const EdgeInsets.fromLTRB(24, 8, 24, 0),
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                accentColor.withValues(
                  alpha: 0.08 + _headerGlowAnimation.value * 0.06,
                ),
                AppColors.resolve(
                  context,
                  const Color(0xFF1E293B),
                  AppColors.lightCard,
                ).withValues(alpha: 0.9),
                AppColors.resolve(
                  context,
                  const Color(0xFF0F172A),
                  AppColors.lightBackground,
                ).withValues(alpha: 0.95),
              ],
            ),
            border: Border.all(
              color: accentColor.withValues(
                alpha: 0.15 + _headerGlowAnimation.value * 0.1,
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: accentColor.withValues(alpha: 0.06),
                blurRadius: 30,
                spreadRadius: -8,
              ),
            ],
          ),
          child: Row(
            children: [
              // Avatar with glow
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: accentColor.withValues(
                        alpha: 0.25 + _headerGlowAnimation.value * 0.15,
                      ),
                      blurRadius: 24,
                      spreadRadius: -2,
                    ),
                  ],
                ),
                child: PersonaColors.buildPersonaAvatar(
                  avatarPath: activePersona.avatarPath,
                  personaId: activePersona.id,
                  radius: 44,
                  iconSize: 36,
                ),
              ),
              const SizedBox(width: 24),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            activePersona.displayLabel,
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary(context),
                              letterSpacing: -0.3,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 10),
                        _buildActiveBadge(accentColor),
                      ],
                    ),
                    if (activePersona.title.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        activePersona.name,
                        style: TextStyle(
                          fontSize: 14,
                          color: accentColor.withValues(alpha: 0.8),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                    if (activePersona.persona.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        activePersona.persona,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary(context),
                          height: 1.4,
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    // Stats chips
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        _buildStatChip(
                          context,
                          Icons.people_outline,
                          '${service.personas.length} persona${service.personas.length != 1 ? 's' : ''}',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Edit button
              IconButton(
                icon: Icon(
                  Icons.edit_outlined,
                  color: accentColor.withValues(alpha: 0.7),
                ),
                tooltip: 'Edit active persona',
                onPressed: () => _startEditing(activePersona),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildActiveBadge(Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withValues(alpha: 0.25), color.withValues(alpha: 0.1)],
        ),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 6, color: color),
          const SizedBox(width: 4),
          Text(
            'Active',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: color,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatChip(BuildContext context, IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.resolve(
          context,
          Colors.white.withValues(alpha: 0.05),
          Colors.black.withValues(alpha: 0.04),
        ),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: AppColors.resolve(
            context,
            Colors.white.withValues(alpha: 0.06),
            AppColors.lightBorder.withValues(alpha: 0.6),
          ),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: AppColors.textTertiary(context)),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: AppColors.textTertiary(context),
            ),
          ),
        ],
      ),
    );
  }

  // ── Persona Card ──────────────────────────────────────────────────────

  Widget _buildPersonaCard(
    BuildContext context,
    UserPersona persona,
    bool isActive,
    UserPersonaService service,
  ) {
    final cardColor = PersonaColors.getColorForPersona(persona.id);

    return _HoverScaleCard(
      isActive: isActive,
      accentColor: cardColor,
      onTap: () => service.setActivePersona(persona.id),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top row: avatar + actions
            Row(
              children: [
                PersonaColors.buildPersonaAvatar(
                  avatarPath: persona.avatarPath,
                  personaId: persona.id,
                  radius: 22,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        persona.displayLabel,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: AppColors.textPrimary(context),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (persona.title.isNotEmpty)
                        Text(
                          persona.name,
                          style: TextStyle(
                            fontSize: 12,
                            color: cardColor.withValues(alpha: 0.7),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                // Actions
                PopupMenuButton<String>(
                  icon: Icon(
                    Icons.more_vert,
                    size: 18,
                    color: AppColors.iconSecondary(context),
                  ),
                  color: AppColors.surfaceContainerOf(context),
                  onSelected: (action) {
                    switch (action) {
                      case 'edit':
                        _startEditing(persona);
                        break;
                      case 'export':
                        _exportPersona(persona);
                        break;
                      case 'delete':
                        _showDeleteConfirmation(context, persona);
                        break;
                    }
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          Icon(
                            Icons.edit,
                            size: 16,
                            color: AppColors.iconPrimary(context),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Edit',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.textPrimary(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'export',
                      child: Row(
                        children: [
                          Icon(
                            Icons.upload,
                            size: 16,
                            color: Colors.cyanAccent,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Export JSON',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.textPrimary(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (service.personas.length > 1)
                      PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(
                              Icons.delete,
                              size: 16,
                              color: Colors.redAccent,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Delete',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.redAccent,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Description
            Expanded(
              child: Text(
                persona.persona.isNotEmpty ? persona.persona : 'No description',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: persona.persona.isNotEmpty
                      ? AppColors.textSecondary(context)
                      : AppColors.textTertiary(context),
                  height: 1.5,
                ),
              ),
            ),
            const SizedBox(height: 8),
            // Bottom row
            Row(
              children: [
                if (!isActive) ...[
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: cardColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: cardColor.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Text(
                      'Select',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: cardColor,
                      ),
                    ),
                  ),
                ] else ...[
                  const Spacer(),
                  _buildActiveBadge(cardColor),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Empty State ───────────────────────────────────────────────────────

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF6366F1).withValues(alpha: 0.08),
              border: Border.all(
                color: const Color(0xFF6366F1).withValues(alpha: 0.15),
              ),
            ),
            child: const Icon(
              Icons.person_add_alt_1,
              size: 44,
              color: Color(0xFF6366F1),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'No personas yet',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppColors.textSecondary(context),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Create a persona to personalize your AI conversations,\nor import one from SillyTavern / Backyard AI.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: AppColors.textTertiary(context),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 28),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton.icon(
                onPressed: () => _startEditing(null),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Create Persona'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6366F1),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 14,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: _importPersona,
                icon: const Icon(
                  Icons.download,
                  size: 18,
                  color: Colors.cyanAccent,
                ),
                label: const Text(
                  'Import JSON',
                  style: TextStyle(color: Colors.cyanAccent),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(
                    color: Colors.cyanAccent.withValues(alpha: 0.3),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 14,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Edit Form ─────────────────────────────────────────────────────────

  Widget _buildEditForm(BuildContext context, {Key? key}) {
    return Center(
      key: key,
      child: SingleChildScrollView(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 680),
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: AppColors.resolve(
              context,
              const Color(0xFF1E293B).withValues(alpha: 0.85),
              AppColors.lightSurface.withValues(alpha: 0.95),
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.borderOf(context)),
            boxShadow: [
              BoxShadow(
                color: AppColors.resolve(
                  context,
                  Colors.black.withValues(alpha: 0.2),
                  Colors.black.withValues(alpha: 0.08),
                ),
                blurRadius: 24,
                spreadRadius: -4,
              ),
            ],
          ),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Avatar picker
                    MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: _pickAvatar,
                        child: Container(
                          width: 110,
                          height: 110,
                          decoration: BoxDecoration(
                            color: AppColors.resolve(
                              context,
                              Colors.white.withValues(alpha: 0.04),
                              Colors.black.withValues(alpha: 0.03),
                            ),
                            shape: BoxShape.circle,
                            image: _avatarPath != null
                                ? DecorationImage(
                                    image: FileImage(File(_avatarPath!)),
                                    fit: BoxFit.cover,
                                  )
                                : null,
                            border: Border.all(
                              color: const Color(
                                0xFF6366F1,
                              ).withValues(alpha: 0.25),
                              width: 2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(
                                  0xFF6366F1,
                                ).withValues(alpha: 0.08),
                                blurRadius: 16,
                                spreadRadius: -2,
                              ),
                            ],
                          ),
                          child: _avatarPath == null
                              ? Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.add_a_photo,
                                      size: 28,
                                      color: AppColors.textTertiary(context),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Avatar',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: AppColors.textTertiary(context),
                                      ),
                                    ),
                                  ],
                                )
                              : null,
                        ),
                      ),
                    ),
                    const SizedBox(width: 24),
                    Expanded(
                      child: Column(
                        children: [
                          _buildFormField(
                            context: context,
                            controller: _titleController,
                            label: 'Title',
                            hint:
                                'Label to distinguish this persona (optional)',
                          ),
                          const SizedBox(height: 14),
                          _buildFormField(
                            context: context,
                            controller: _nameController,
                            label: 'Name',
                            hint: 'Name sent to the AI',
                            validator: (v) =>
                                v?.isEmpty ?? true ? 'Name is required' : null,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                // Persona text — expandable
                _buildExpandableFormField(
                  context: context,
                  controller: _personaController,
                  label: 'Persona Text (injected into AI context)',
                  hint:
                      'Detailed persona info the AI will know about you — '
                      'appearance, traits, background, preferences...',
                  helperText:
                      'This text is sent to the AI in every conversation. '
                      'Import from SillyTavern or Backyard AI auto-populates this.',
                ),
                const SizedBox(height: 28),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _cancelEditing,
                      child: Text(
                        'Cancel',
                        style: TextStyle(
                          color: AppColors.textSecondary(context),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    ElevatedButton.icon(
                      onPressed: _savePersona,
                      icon: const Icon(Icons.save, size: 18),
                      label: const Text('Save Persona'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6366F1),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 28,
                          vertical: 14,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFormField({
    required BuildContext context,
    required TextEditingController controller,
    required String label,
    String? hint,
    int maxLines = 1,
    String? Function(String?)? validator,
    String? helperText,
  }) {
    return TextFormField(
      controller: controller,
      style: TextStyle(color: AppColors.textPrimary(context), fontSize: 14),
      maxLines: maxLines,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        hintStyle: TextStyle(
          color: AppColors.textTertiary(context),
          fontSize: 13,
        ),
        labelStyle: TextStyle(color: AppColors.textSecondary(context)),
        helperText: helperText,
        helperStyle: TextStyle(
          color: AppColors.textTertiary(context),
          fontSize: 11,
        ),
        helperMaxLines: 2,
        filled: true,
        fillColor: AppColors.surfaceContainerOf(context),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: AppColors.borderOf(context)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: AppColors.borderOf(context)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF6366F1), width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
      ),
    );
  }

  Widget _buildExpandableFormField({
    required BuildContext context,
    required TextEditingController controller,
    required String label,
    String? hint,
    String? helperText,
  }) {
    return Stack(
      children: [
        _buildFormField(
          context: context,
          controller: controller,
          label: label,
          hint: hint,
          maxLines: 5,
          helperText: helperText,
        ),
        Positioned(
          top: 4,
          right: 4,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _showExpandPersonaDialog(controller),
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFF6366F1).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(
                  Icons.open_in_full,
                  size: 16,
                  color: Color(0xFF6366F1),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _showExpandPersonaDialog(TextEditingController controller) {
    final tempController = TextEditingController(text: controller.text);
    showDialog(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 700, maxHeight: 600),
          decoration: BoxDecoration(
            color: AppColors.surfaceOf(dialogContext),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.borderOf(dialogContext)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                child: Row(
                  children: [
                    Text(
                      'Edit Persona Text',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary(dialogContext),
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: Icon(
                        Icons.close,
                        color: AppColors.textSecondary(dialogContext),
                      ),
                      onPressed: () => Navigator.of(dialogContext).pop(),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: AppColors.borderOf(dialogContext)),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: TextField(
                    controller: tempController,
                    style: TextStyle(
                      color: AppColors.textPrimary(dialogContext),
                      fontSize: 14,
                    ),
                    maxLines: null,
                    decoration: InputDecoration(
                      hintText: 'Enter detailed persona info...',
                      hintStyle: TextStyle(
                        color: AppColors.textTertiary(dialogContext),
                      ),
                      filled: true,
                      fillColor: AppColors.surfaceContainerOf(dialogContext),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(
                          color: AppColors.borderOf(dialogContext),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(
                          color: AppColors.borderOf(dialogContext),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(
                          color: Color(0xFF6366F1),
                          width: 1.5,
                        ),
                      ),
                      contentPadding: const EdgeInsets.all(14),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: Text(
                        'Cancel',
                        style: TextStyle(
                          color: AppColors.textSecondary(dialogContext),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: () {
                        controller.text = tempController.text;
                        Navigator.of(dialogContext).pop();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6366F1),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text('Save'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Dialogs ───────────────────────────────────────────────────────────

  void _showDeleteConfirmation(BuildContext context, UserPersona persona) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceOf(context),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Delete Persona',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary(context),
          ),
        ),
        content: RichText(
          text: TextSpan(
            style: TextStyle(
              color: AppColors.textSecondary(context),
              height: 1.5,
            ),
            children: [
              TextSpan(text: 'Are you sure you want to delete '),
              TextSpan(
                text: '"${persona.name}"',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary(context),
                ),
              ),
              TextSpan(text: '? This cannot be undone.'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'Cancel',
              style: TextStyle(color: AppColors.textSecondary(context)),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Provider.of<UserPersonaService>(
                context,
                listen: false,
              ).deletePersona(persona.id);
              Navigator.of(context).pop();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

}

// ═══════════════════════════════════════════════════════════════════════════
// Hover Scale Card — glassmorphic persona card with micro-animations
// ═══════════════════════════════════════════════════════════════════════════

class _HoverScaleCard extends StatefulWidget {
  final bool isActive;
  final Color accentColor;
  final VoidCallback onTap;
  final Widget child;

  const _HoverScaleCard({
    required this.isActive,
    required this.accentColor,
    required this.onTap,
    required this.child,
  });

  @override
  State<_HoverScaleCard> createState() => _HoverScaleCardState();
}

class _HoverScaleCardState extends State<_HoverScaleCard>
    with SingleTickerProviderStateMixin {
  bool _isHovered = false;
  late AnimationController _borderAnimController;
  late Animation<double> _borderAnimation;

  @override
  void initState() {
    super.initState();
    _borderAnimController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    _borderAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _borderAnimController, curve: Curves.linear),
    );
    if (widget.isActive) _borderAnimController.repeat();
  }

  @override
  void didUpdateWidget(covariant _HoverScaleCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !_borderAnimController.isAnimating) {
      _borderAnimController.repeat();
    } else if (!widget.isActive && _borderAnimController.isAnimating) {
      _borderAnimController.stop();
      _borderAnimController.reset();
    }
  }

  @override
  void dispose() {
    _borderAnimController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _isHovered ? 1.025 : 1.0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          child: AnimatedBuilder(
            animation: _borderAnimation,
            builder: (context, child) {
              return Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: _isHovered
                      ? AppColors.resolve(
                          context,
                          const Color(0xFF1E293B),
                          AppColors.lightCard,
                        )
                      : AppColors.resolve(
                          context,
                          const Color(0xFF1E293B).withValues(alpha: 0.7),
                          AppColors.lightCard.withValues(alpha: 0.85),
                        ),
                  border: Border.all(
                    color: widget.isActive
                        ? widget.accentColor.withValues(
                            alpha: 0.35 + _borderAnimation.value * 0.15,
                          )
                        : _isHovered
                        ? AppColors.borderOf(context).withValues(alpha: 0.5)
                        : AppColors.borderOf(context),
                    width: widget.isActive ? 1.5 : 1,
                  ),
                  boxShadow: [
                    if (_isHovered || widget.isActive)
                      BoxShadow(
                        color: widget.isActive
                            ? widget.accentColor.withValues(alpha: 0.08)
                            : AppColors.resolve(
                                context,
                                Colors.white.withValues(alpha: 0.02),
                                Colors.black.withValues(alpha: 0.04),
                              ),
                        blurRadius: 16,
                        spreadRadius: -4,
                      ),
                  ],
                ),
                child: child,
              );
            },
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
