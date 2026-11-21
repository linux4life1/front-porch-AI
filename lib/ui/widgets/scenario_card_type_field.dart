// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';

const scenarioSettingHelp = 'Leave blank to choose the setting in chat.';
const scenarioOpeningHelp = 'With no greetings, the player speaks first.';
const scenarioRulesHelp =
    'Chat uses the first 2,000 characters. The card keeps the full text.';
const scenarioNewChatHelp =
    'New chats use changes to card type, setting, scene notes, narration style, '
    'facilitation rules and reply examples. Advanced prompts can affect existing chats.';
const scenarioGroupScopeHelp = 'These edits apply only to this group member.';

class ScenarioCardTypeField extends StatefulWidget {
  const ScenarioCardTypeField({
    super.key,
    required this.scenario,
    required this.onChanged,
    this.unsupported = false,
  });

  final bool scenario;
  final bool unsupported;
  final ValueChanged<bool> onChanged;

  @override
  State<ScenarioCardTypeField> createState() => _ScenarioCardTypeFieldState();
}

class _ScenarioCardTypeFieldState extends State<ScenarioCardTypeField> {
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
          value: widget.unsupported ? null : widget.scenario,
          hint: const Text('Unsupported card type'),
          onChanged: widget.unsupported
              ? null
              : (value) {
                  if (value != null) widget.onChanged(value);
                },
          items: const [
            DropdownMenuItem(value: false, child: Text('Character')),
            DropdownMenuItem(value: true, child: Text('Scenario')),
          ],
        ),
      ),
      Text(
        widget.unsupported
            ? 'This card’s type is preserved. This version opens it as Character.'
            : widget.scenario
            ? 'Runs a scene without a primary character and leaves your choices to you.'
            : 'Plays a character in the story.',
      ),
    ],
  );
}
