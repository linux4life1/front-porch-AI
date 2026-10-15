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

import 'package:front_porch_ai/services/chargen/chargen.dart';
import 'package:front_porch_ai/ui/character_creator/widgets/creator_input_label.dart';
import 'package:front_porch_ai/ui/theme/studio_colors.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

/// The name dialog Save as template and Rename share
/// (docs/design/creator-ui-spec.md, "Save-as-template dialog"): the
/// `TEMPLATE NAME` steer field, and under it the name's problem in `bad` or
/// the replace caption in amber. The confirm button is off while the name
/// has a problem or the write is running. Pops `true` once [submit] is done.
class TemplateNameDialog extends StatefulWidget {
  const TemplateNameDialog({
    super.key,
    required this.title,
    required this.confirmLabel,
    required this.initialName,
    required this.check,
    required this.submit,
    required this.failure,
    this.body,
  });

  final String title;
  final String? body;
  final String confirmLabel;
  final String initialName;

  /// The name's problem, or whether saving it replaces a template.
  final ({String? problem, bool replaces}) Function(String name) check;

  /// Writes the template. A [TemplateRefused] keeps the dialog open with
  /// its message under the field; any other error with [failure].
  final Future<void> Function(String name) submit;

  /// What the field says when the write fails for another reason.
  final String failure;

  @override
  State<TemplateNameDialog> createState() => _TemplateNameDialogState();
}

class _TemplateNameDialogState extends State<TemplateNameDialog> {
  /// The caret after the prefilled name, as the sketch draws the field.
  late final _name = TextEditingController(text: widget.initialName)
    ..selection = TextSelection.collapsed(offset: widget.initialName.length);

  /// Why the last write did not happen; cleared by the next keystroke.
  String? _failed;
  bool _busy = false;

  /// An empty field stays quiet until it is edited or Enter is pressed;
  /// a prefilled name shows its problem at once.
  late bool _touched = widget.initialName.isNotEmpty;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    final name = _name.text;
    if (_busy) return;
    if (widget.check(name).problem != null) {
      setState(() => _touched = true);
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.submit(name);
      if (mounted) Navigator.of(context).pop(true);
    } on TemplateRefused catch (e) {
      if (mounted) setState(() => _failed = e.message);
    } catch (e, st) {
      debugPrint('CharacterCreator: template write failed: $e\n$st');
      if (mounted) setState(() => _failed = widget.failure);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final verdict = widget.check(_name.text);
    final problem = _failed ?? (_touched ? verdict.problem : null);
    final caption =
        problem ?? (verdict.replaces ? kTemplateReplacesCaption : null);
    final canSave = verdict.problem == null && !_busy;
    return WarmDialog(
      title: widget.title,
      icon: Icons.bookmark_border,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.body != null) ...[
            WarmDialogText(widget.body!),
            const SizedBox(height: 16),
          ],
          const CreatorInputLabel('TEMPLATE NAME'),
          const SizedBox(height: 6),
          _field(context),
          if (caption != null) ...[
            const SizedBox(height: 6),
            Text(
              caption,
              key: const ValueKey('template-name-caption'),
              style: TextStyle(
                fontSize: 12,
                height: 1.5,
                color: problem != null
                    ? StudioColors.badOf(context)
                    : StudioColors.amberOf(context),
              ),
            ),
          ],
        ],
      ),
      actions: [
        warmDialogCancel(context),
        warmDialogConfirm(
          context,
          key: const ValueKey('template-name-confirm'),
          label: widget.confirmLabel,
          onPressed: canSave ? _confirm : null,
        ),
      ],
    );
  }

  /// The spec's steer field: `raise` fill, no border, radius 12, 44px.
  Widget _field(BuildContext context) => SizedBox(
    height: 44,
    child: AppTextField(
      key: const ValueKey('template-name-field'),
      controller: _name,
      autofocus: true,
      maxLines: 1,
      textAlignVertical: TextAlignVertical.center,
      onChanged: (_) => setState(() {
        _failed = null;
        _touched = true;
      }),
      onSubmitted: (_) => _confirm(),
      style: TextStyle(
        fontSize: 14,
        letterSpacing: 0,
        color: StudioColors.inkOf(context),
      ),
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: StudioColors.raiseOf(context),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 13,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    ),
  );
}
