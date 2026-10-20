// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';

import 'package:front_porch_ai/ui/chat_components/prompt_source_panes.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

/// The three named presets of the new-chat prompt picker (SOW Phase 1).
/// Each maps to the per-chat pair (systemPromptSource, promptAmendments).
enum PromptPreset {
  cardAmendments('Card + my amendments', 'Recommended · what happens today'),
  cardOnly('Card only', "Author's prompt, nothing added"),
  userPrompt('My prompt', "Replaces the card's prompt");

  const PromptPreset(this.label, this.sub);

  final String label;
  final String sub;

  bool get usesCard => this != userPrompt;
  bool get usesAmendments => this != cardOnly;

  String get wireName => switch (this) {
    PromptPreset.cardAmendments => 'card+amend',
    PromptPreset.cardOnly => 'card',
    PromptPreset.userPrompt => 'user',
  };

  static PromptPreset fromWire(String wire) => switch (wire) {
    'card' => PromptPreset.cardOnly,
    'user' => PromptPreset.userPrompt,
    _ => PromptPreset.cardAmendments,
  };
}

/// The picker's answer. [askEveryChat] wins over [remember]: it applies the
/// preset to this chat and clears the remembered choice so the next new
/// chat asks again.
class PromptSourceChoice {
  const PromptSourceChoice({
    required this.preset,
    required this.remember,
    required this.askEveryChat,
  });

  final PromptPreset preset;
  final bool remember;
  final bool askEveryChat;
}

/// Opens the picker. A null result (dismissed) keeps this chat on today's
/// inherited behavior; the next new chat asks again.
Future<PromptSourceChoice?> showPromptSourcePicker(
  BuildContext context, {
  required String characterName,
  required String cardPrompt,
  required String userPrompt,
  required String amendment,
}) {
  return showWarmDialogOf<PromptSourceChoice>(
    context,
    builder: (_) => PromptSourcePickerDialog(
      characterName: characterName,
      cardPrompt: cardPrompt,
      userPrompt: userPrompt,
      amendment: amendment,
    ),
  );
}

/// Overflow contract (approved design): the dialog is capped at 85% of the
/// viewport height, the body scrolls, the footer never leaves the screen,
/// and both prompts show in full inside their own scrollable panes.
class PromptSourcePickerDialog extends StatefulWidget {
  const PromptSourcePickerDialog({
    super.key,
    required this.characterName,
    required this.cardPrompt,
    required this.userPrompt,
    required this.amendment,
  });

  final String characterName;
  final String cardPrompt;
  final String userPrompt;
  final String amendment;

  @override
  State<PromptSourcePickerDialog> createState() =>
      _PromptSourcePickerDialogState();
}

class _PromptSourcePickerDialogState extends State<PromptSourcePickerDialog> {
  PromptPreset _preset = PromptPreset.cardAmendments;
  bool _remember = false;
  final ScrollController _cardScroll = ScrollController();
  final ScrollController _userScroll = ScrollController();

  @override
  void dispose() {
    _cardScroll.dispose();
    _userScroll.dispose();
    super.dispose();
  }

  String get _base => _preset.usesCard ? widget.cardPrompt : widget.userPrompt;

  String get _baseName => _preset.usesCard ? 'card prompt' : 'your prompt';

  int get _approxTokens =>
      ((_base.length +
                  (_preset.usesAmendments && widget.amendment.trim().isNotEmpty
                      ? widget.amendment.trim().length
                      : 0)) /
              4)
          .round();

  void _pop(PromptSourceChoice choice) => Navigator.of(context).pop(choice);

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height * 0.85;
    return Dialog(
      key: const ValueKey('prompt-source-dialog'),
      backgroundColor: AppColors.surfaceOf(context),
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: AppColors.borderOf(context)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 860),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _head(context),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _segmented(context),
                      const SizedBox(height: 14),
                      PromptSourcePanes(
                        cardPrompt: widget.cardPrompt,
                        userPrompt: widget.userPrompt,
                        usesCard: _preset.usesCard,
                        cardController: _cardScroll,
                        userController: _userScroll,
                      ),
                      const SizedBox(height: 14),
                      PromptResolvedPreview(
                        base: _base,
                        baseName: _baseName,
                        amendment: widget.amendment,
                        usesAmendments: _preset.usesAmendments,
                        approxTokens: _approxTokens,
                      ),
                    ],
                  ),
                ),
              ),
              _footer(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _head(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Choose the system prompt for this chat',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary(context),
            ),
          ),
          const SizedBox(height: 2),
          Text.rich(
            TextSpan(
              text: 'New chat with ',
              children: [
                TextSpan(
                  text: widget.characterName,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const TextSpan(
                  text:
                      ' · their card ships its own system prompt. Your global '
                      'amendments apply unless you turn them off.',
                ),
              ],
            ),
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _segmented(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < 560;
        final buttons = PromptPreset.values.map((preset) {
          final on = preset == _preset;
          return Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => setState(() => _preset = preset),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: on
                      ? AppColors.surfaceContainerOf(context)
                      : AppColors.backgroundOf(context),
                  border: Border.all(
                    color: on
                        ? AppColors.porchTerracottaOf(context)
                        : AppColors.borderOf(context),
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    Text(
                      preset.label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: on
                            ? AppColors.porchTerracottaOf(context)
                            : AppColors.textSecondary(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      preset.sub,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 10.5,
                        color: on
                            ? AppColors.textSecondary(context)
                            : AppColors.textTertiary(context),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList();
        return stacked
            ? Column(children: buttons)
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final b in buttons) ...[
                    b,
                    if (b != buttons.last) const SizedBox(width: 6),
                  ],
                ],
              );
      },
    );
  }

  Widget _footer(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.cardOf(context),
        border: Border(top: BorderSide(color: AppColors.borderOf(context))),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(13)),
      ),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: () => setState(() => _remember = !_remember),
              child: Row(
                children: [
                  Checkbox(
                    value: _remember,
                    onChanged: (v) => setState(() => _remember = v ?? false),
                  ),
                  Expanded(
                    child: Text(
                      'Remember my choice for ${widget.characterName}',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary(context),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          OutlinedButton(
            onPressed: () => _pop(
              PromptSourceChoice(
                preset: _preset,
                remember: false,
                askEveryChat: true,
              ),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textSecondary(context),
              side: BorderSide(color: AppColors.borderOf(context)),
            ),
            child: const Text('Ask me every chat'),
          ),
          const SizedBox(width: 12),
          FilledButton(
            onPressed: () => _pop(
              PromptSourceChoice(
                preset: _preset,
                remember: _remember,
                askEveryChat: false,
              ),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.porchAmberOf(context),
              foregroundColor: AppColors.onAccentOf(context),
            ),
            child: const Text('Start chat'),
          ),
        ],
      ),
    );
  }
}
