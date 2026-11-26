// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';

const botScopeHelp =
    'Describe the tasks this Bot handles and the context it should use.';
const botOpeningHelp = 'With no greetings, you speak first.';
const botInstructionsHelp =
    'Chat uses the first 2,000 characters. The card keeps the full text.';
const botNewChatHelp =
    'New chats use changes to card type, scope, role, personality, '
    'behavior instructions and reply examples. Advanced prompts can affect existing chats.';
const botGroupScopeHelp = 'These edits apply only to this group member.';

class BotCardTypeField extends StatefulWidget {
  const BotCardTypeField({
    super.key,
    required this.bot,
    required this.onChanged,
    this.unsupported = false,
  });

  final bool bot;
  final bool unsupported;
  final ValueChanged<bool> onChanged;

  @override
  State<BotCardTypeField> createState() => _BotCardTypeFieldState();
}

class _BotCardTypeFieldState extends State<BotCardTypeField> {
  final _focus = FocusNode(debugLabel: 'Card type');

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const ExcludeSemantics(child: Text('Card type')),
      Semantics(
        label: 'Card type',
        child: DropdownButton<bool>(
          isExpanded: true,
          focusNode: _focus,
          value: widget.unsupported ? null : widget.bot,
          hint: const Text('Unsupported card type'),
          onChanged: widget.unsupported
              ? null
              : (value) {
                  if (value != null) widget.onChanged(value);
                },
          items: const [
            DropdownMenuItem(value: false, child: Text('Character')),
            DropdownMenuItem(value: true, child: Text('Bot')),
          ],
        ),
      ),
      Text(
        widget.unsupported
            ? 'This card’s type is preserved. This version opens it as Character.'
            : widget.bot
            ? 'Speaks directly to you in its own voice.'
            : 'Plays a character in the story.',
      ),
    ],
  );
}
