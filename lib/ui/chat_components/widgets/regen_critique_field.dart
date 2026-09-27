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

import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/warm_dialog.dart';

/// Optional reject reason. Grows downward so the full note stays readable.
/// Lives in [showRegenCritiqueDialog], not on the bubble.
class RegenCritiqueField extends StatelessWidget {
  const RegenCritiqueField({
    super.key,
    required this.controller,
    this.onSubmitted,
    this.autofocus = true,
  });

  final TextEditingController controller;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final amber = AppColors.porchAmberOf(context);
    return TextField(
      key: const Key('regen-critique-field'),
      controller: controller,
      autofocus: autofocus,
      minLines: 3,
      maxLines: 8,
      maxLength: 500,
      keyboardType: TextInputType.multiline,
      textInputAction: TextInputAction.newline,
      onSubmitted: onSubmitted,
      style: TextStyle(fontSize: 13, color: AppColors.textPrimary(context)),
      decoration: InputDecoration(
        hintText: 'why this take was wrong — optional',
        hintStyle: TextStyle(
          fontSize: 13,
          color: AppColors.textTertiary(context),
        ),
        isDense: true,
        counterText: '',
        filled: true,
        fillColor: AppColors.surfaceContainerOf(context),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 10,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: amber.withValues(alpha: 0.4)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: amber.withValues(alpha: 0.4)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: amber),
        ),
      ),
    );
  }
}

/// What the regenerate dialog confirmed. [webQuery] and [wikiQuery] are set
/// only when the lookup field has words. Empty means an ordinary reroll.
class RegenCritiqueResult {
  const RegenCritiqueResult({
    required this.critique,
    this.webQuery,
    this.wikiQuery,
  });

  final String critique;
  final String? webQuery;
  final String? wikiQuery;
}

/// Session id for the wiki URL, or null when this [ChatService] is a test
/// double that does not implement the getter.
String? lookupSessionId(ChatService chat) {
  try {
    return chat.currentSessionId;
  } on NoSuchMethodError {
    return null;
  }
}

/// Whether the regenerate dialog may offer web and wiki lookups.
({bool web, bool wiki}) lookupRegenSources(
  StorageService storage,
  ChatService chat,
) {
  return (
    web: storage.webSearchSettings.webSearchDefault,
    wiki:
        parseWikiBaseUrl(
          storage.webSearchSettings.wikiUrlForChat(lookupSessionId(chat)),
        ) !=
        null,
  );
}

/// Cancel → `null`. Confirm → the note plus any named lookup.
Future<RegenCritiqueResult?> showRegenCritiqueDialog(
  BuildContext context, {
  bool webEnabled = false,
  bool wikiEnabled = false,
}) {
  return showDialog<RegenCritiqueResult>(
    context: context,
    builder: (ctx) =>
        _RegenCritiqueDialog(webEnabled: webEnabled, wikiEnabled: wikiEnabled),
  );
}

class _RegenCritiqueDialog extends StatefulWidget {
  const _RegenCritiqueDialog({
    required this.webEnabled,
    required this.wikiEnabled,
  });

  final bool webEnabled;
  final bool wikiEnabled;

  @override
  State<_RegenCritiqueDialog> createState() => _RegenCritiqueDialogState();
}

class _RegenCritiqueDialogState extends State<_RegenCritiqueDialog> {
  final _controller = TextEditingController();
  final _lookup = TextEditingController();
  late bool _wiki = !widget.webEnabled && widget.wikiEnabled;

  bool get _showLookup => widget.webEnabled || widget.wikiEnabled;

  @override
  void dispose() {
    _controller.dispose();
    _lookup.dispose();
    super.dispose();
  }

  void _pop() {
    final query = _lookup.text.trim();
    final web = widget.webEnabled && !_wiki && query.isNotEmpty ? query : null;
    final wiki = widget.wikiEnabled && _wiki && query.isNotEmpty ? query : null;
    Navigator.of(context).pop(
      RegenCritiqueResult(
        critique: _controller.text,
        webQuery: web,
        wikiQuery: wiki,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tint = AppColors.porchAmberOf(context);
    return AlertDialog(
      backgroundColor: AppColors.surfaceOf(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: tint.withValues(alpha: 0.5)),
      ),
      title: Row(
        children: [
          Icon(Icons.refresh, color: tint, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Regenerate',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary(context),
              ),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const WarmDialogText(
              'Optional note for this swipe. Leave blank to just try again.',
            ),
            const SizedBox(height: 12),
            RegenCritiqueField(
              controller: _controller,
              onSubmitted: (_) => _pop(),
            ),
            if (_showLookup) ...[
              const SizedBox(height: 12),
              _LookupRow(
                webEnabled: widget.webEnabled,
                wikiEnabled: widget.wikiEnabled,
                wiki: _wiki,
                controller: _lookup,
                onWiki: (wiki) => setState(() => _wiki = wiki),
              ),
            ],
          ],
        ),
      ),
      actions: [
        warmDialogCancel(context),
        warmDialogConfirm(
          context,
          key: const Key('regen-critique-confirm'),
          label: 'Regenerate',
          onPressed: _pop,
        ),
      ],
    );
  }
}

class _LookupRow extends StatelessWidget {
  const _LookupRow({
    required this.webEnabled,
    required this.wikiEnabled,
    required this.wiki,
    required this.controller,
    required this.onWiki,
  });

  final bool webEnabled;
  final bool wikiEnabled;
  final bool wiki;
  final TextEditingController controller;
  final ValueChanged<bool> onWiki;

  @override
  Widget build(BuildContext context) {
    final tint = AppColors.porchAmberOf(context);
    final showToggle = webEnabled;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Look this up',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary(context),
          ),
        ),
        const SizedBox(height: 6),
        if (showToggle)
          Row(
            children: [
              _SourceChip(
                key: const Key('regen-lookup-web'),
                label: 'Web',
                selected: !wiki,
                onTap: () => onWiki(false),
              ),
              const SizedBox(width: 8),
              _SourceChip(
                key: const Key('regen-lookup-wiki'),
                label: 'Her wiki',
                selected: wiki && wikiEnabled,
                enabled: wikiEnabled,
                onTap: wikiEnabled ? () => onWiki(true) : null,
              ),
            ],
          )
        else
          Text(
            'Her wiki',
            key: const Key('regen-lookup-wiki'),
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary(context),
            ),
          ),
        const SizedBox(height: 8),
        TextField(
          key: const Key('regen-lookup-query'),
          controller: controller,
          maxLength: 256,
          style: TextStyle(fontSize: 13, color: AppColors.textPrimary(context)),
          decoration: InputDecoration(
            hintText: 'the exact words to look up — optional',
            hintStyle: TextStyle(
              fontSize: 13,
              color: AppColors.textTertiary(context),
            ),
            isDense: true,
            counterText: '',
            filled: true,
            fillColor: AppColors.surfaceContainerOf(context),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 10,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: tint.withValues(alpha: 0.4)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: tint.withValues(alpha: 0.4)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: tint),
            ),
          ),
        ),
      ],
    );
  }
}

class _SourceChip extends StatelessWidget {
  const _SourceChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.enabled = true,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final tint = AppColors.porchAmberOf(context);
    final fg = !enabled
        ? AppColors.textTertiary(context)
        : selected
        ? AppColors.onChaosAccent
        : AppColors.textPrimary(context);
    return Material(
      color: !enabled
          ? AppColors.surfaceContainerOf(context)
          : selected
          ? tint
          : AppColors.surfaceContainerOf(context),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: fg,
            ),
          ),
        ),
      ),
    );
  }
}

/// Opens the regenerate dialog with web and wiki choices for this chat.
Future<void> promptLookupRegen(
  BuildContext context,
  ChatService chatService,
  Future<void> Function({String? critique, String? webQuery, String? wikiQuery})
  regen,
) {
  final sources = lookupRegenSources(
    context.read<StorageService>(),
    chatService,
  );
  return promptRegenCritiqueThen(
    context,
    (c) => regen(critique: c),
    webEnabled: sources.web,
    wikiEnabled: sources.wiki,
    onLookup: (c, {webQuery, wikiQuery}) =>
        regen(critique: c, webQuery: webQuery, wikiQuery: wikiQuery),
  );
}

/// Pops the critique dialog, then [onRegen]. Cancel does nothing.
/// [onLookup] runs instead when the lookup field has words.
Future<void> promptRegenCritiqueThen(
  BuildContext context,
  void Function(String critique) onRegen, {
  bool webEnabled = false,
  bool wikiEnabled = false,
  void Function(String critique, {String? webQuery, String? wikiQuery})?
  onLookup,
}) async {
  final result = await showRegenCritiqueDialog(
    context,
    webEnabled: webEnabled,
    wikiEnabled: wikiEnabled,
  );
  if (result == null || !context.mounted) return;
  final web = result.webQuery;
  final wiki = result.wikiQuery;
  if (onLookup != null &&
      ((web != null && web.isNotEmpty) || (wiki != null && wiki.isNotEmpty))) {
    onLookup(result.critique, webQuery: web, wikiQuery: wiki);
    return;
  }
  onRegen(result.critique);
}
