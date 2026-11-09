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

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/settings/dialogs/prompt_delete_dialog.dart';
import 'package:front_porch_ai/ui/settings/dialogs/prompt_save_dialog.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

import 'package:front_porch_ai/ui/theme/app_corners.dart';
import 'section_header.dart';

/// One Settings prompt slot over the shared pool of saved prompts: a badge
/// saying where the text came from, Load a saved prompt, the box, then Save
/// (update the loaded prompt), Save as new and Reset to built-in. Built-ins
/// are never in the pool, so no Save reaches them.
class PromptSlotCard extends StatefulWidget {
  const PromptSlotCard({
    super.key,
    required this.slot,
    required this.title,
    required this.helper,
    required this.fieldLabel,
    this.controller,
  });

  final PromptSlot slot;
  final String title;
  final String helper;
  final String fieldLabel;

  /// The box's controller when the page owns it (the one-to-one slot);
  /// otherwise the card makes its own.
  final TextEditingController? controller;

  @override
  State<PromptSlotCard> createState() => _PromptSlotCardState();
}

class _PromptSlotCardState extends State<PromptSlotCard> {
  TextEditingController? _own;

  TextEditingController get _controller => widget.controller ?? _own!;

  StorageService get _storage => context.read<StorageService>();

  @override
  void initState() {
    super.initState();
    if (widget.controller == null) {
      _own = TextEditingController(text: widget.slot.shownText(_storage));
    }
  }

  @override
  void dispose() {
    _own?.dispose();
    super.dispose();
  }

  Future<void> _guard(Future<void> Function() write) async {
    try {
      await write();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save the prompt: $error')),
      );
    }
  }

  Future<void> _apply(String text, String? name) => _guard(() async {
    _controller.text = text;
    await widget.slot.writeText(_storage, text);
    await widget.slot.writeSavedName(_storage, name);
  });

  void _load(String? name) {
    if (name == null) return;
    final prompt = _storage.presetSettings.savedPrompts
        .where((p) => p['name'] == name)
        .firstOrNull;
    if (prompt == null) return;
    _apply(prompt['content'] ?? '', name);
  }

  void _saveOver(String name) => _guard(() async {
    await _storage.presetSettings.savePrompt(name, _controller.text);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Prompt "$name" updated.')));
  });

  void _saveAsNew() => showSavePromptDialog(
    context,
    _storage,
    content: _controller.text,
    onSaved: (name) => _guard(() => widget.slot.writeSavedName(_storage, name)),
  );

  Future<void> _reset(BuiltInPrompt builtIn) async {
    final messenger = ScaffoldMessenger.of(context);
    final before = _controller.text;
    final beforeName = widget.slot.savedName(_storage);
    await _apply(builtIn.text, null);
    if (before == builtIn.text) return;
    // Undo must show now, not queue behind an earlier "saved" note.
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text('Reset to ${builtIn.label}.'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            if (mounted) _apply(before, beforeName);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final storage = context.watch<StorageService>();
    final slot = widget.slot;
    final status = slot.status(storage);
    final pool = userSavedPrompts(storage.presetSettings.savedPrompts);
    final name = slot.savedName(storage);
    final loaded = pool.any((p) => p['name'] == name) ? name : null;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardOf(context),
        borderRadius: AppCorners.of(context).circular(12),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                widget.title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary(context),
                ),
              ),
              _SlotBadge(slot: slot, status: status),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            widget.helper,
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary(context),
              height: 1.45,
            ),
          ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                // Re-seeded when the slot's pick changes elsewhere (a reset,
                // a delete, the web app).
                key: ValueKey('${slot.name}-$loaded'),
                initialValue: loaded,
                isExpanded: true,
                hint: Text(
                  pool.isEmpty
                      ? 'No saved prompts yet'
                      : 'Load a saved prompt...',
                  style: const TextStyle(fontSize: 13),
                ),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: AppColors.cardOf(context),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ),
                items: [
                  for (final p in pool)
                    DropdownMenuItem<String>(
                      value: p['name'],
                      child: Text(p['name']!, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: _load,
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Delete a saved prompt',
              icon: Icon(Icons.delete_outline, color: AppColors.logError),
              onPressed: () => showDeletePromptDialog(context, storage),
            ),
          ],
        ),
        const SizedBox(height: 8),
        AppTextField(
          controller: _controller,
          minLines: 3,
          maxLines: 6,
          style: Theme.of(context).textTheme.bodyMedium,
          decoration: InputDecoration(
            labelText: widget.fieldLabel,
            filled: true,
            fillColor: AppColors.cardOf(context),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
          onChanged: (text) => _guard(() => slot.writeText(_storage, text)),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (status case OnSavedPrompt(:final name, edited: true))
              FilledButton(
                onPressed: () => _saveOver(name),
                child: Text('Save to "$name"'),
              ),
            OutlinedButton(
              onPressed: _saveAsNew,
              child: const Text('Save as new...'),
            ),
            _ResetButton(builtIns: slot.builtIns, onReset: _reset),
          ],
        ),
      ],
    ),
    );
  }
}

class _SlotBadge extends StatelessWidget {
  const _SlotBadge({required this.slot, required this.status});

  final PromptSlot slot;
  final PromptSlotStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, strong) = switch (status) {
      OnBuiltInPrompt(:final label) => ('Built-in: $label', false),
      OnSavedPrompt(:final name, edited: false) => (name, true),
      OnSavedPrompt(:final name, edited: true) => ('$name (edited)', true),
      OnCustomPrompt() => ('Not saved', false),
    };
    final accent = AppColors.formAccentOf(context);
    return Container(
      key: ValueKey('prompt-slot-badge-${slot.name}'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: strong ? accent : null,
        border: Border.all(
          color: strong ? accent : AppColors.textTertiary(context),
        ),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: strong
              ? AppColors.onAccentOf(context)
              : AppColors.textPrimary(context),
        ),
      ),
    );
  }
}

/// One built-in: a plain button. Several: a menu naming each.
class _ResetButton extends StatelessWidget {
  const _ResetButton({required this.builtIns, required this.onReset});

  final List<BuiltInPrompt> builtIns;
  final void Function(BuiltInPrompt) onReset;

  @override
  Widget build(BuildContext context) {
    if (builtIns.length == 1) {
      return OutlinedButton(
        onPressed: () => onReset(builtIns.single),
        child: const Text('Reset to built-in'),
      );
    }
    return MenuAnchor(
      menuChildren: [
        for (final b in builtIns)
          MenuItemButton(onPressed: () => onReset(b), child: Text(b.label)),
      ],
      builder: (context, menu, _) => OutlinedButton.icon(
        onPressed: () => menu.isOpen ? menu.close() : menu.open(),
        icon: const Icon(Icons.arrow_drop_down, size: 18),
        label: const Text('Reset to built-in'),
      ),
    );
  }
}
