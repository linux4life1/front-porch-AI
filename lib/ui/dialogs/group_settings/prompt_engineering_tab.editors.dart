// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

part of 'prompt_engineering_tab.dart';

extension _GroupPromptEditors on _GroupPromptEngineeringTabState {
  /// The member's portrait, or its initial when it has none (or only the
  /// flat placeholder a character made without a portrait carries).
  Widget _memberAvatar(CharacterCard c, int index) => RealPortrait(
    file: c.imagePath != null ? File(c.imagePath!) : null,
    portrait: (_, file) => CircleAvatar(
      radius: 16,
      backgroundColor: _charColor(index),
      backgroundImage: FileImage(file),
    ),
    noPortrait: (_) => CircleAvatar(
      radius: 16,
      backgroundColor: _charColor(index),
      child: Text(
        c.name.isNotEmpty ? c.name[0].toUpperCase() : '?',
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
    ),
  );

  Widget _buildCharacterNoteEditor(CharacterCard c, int index) {
    final noteCtrl = _getOrCreateNoteController(c);
    final strength = _perCharStrengths.putIfAbsent(
      c,
      () => widget.chatService.getAuthorNoteStrengthForGroupCharacter(c),
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.cardOf(context),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: avatar + name
          Row(
            children: [
              _memberAvatar(c, index),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  c.name,
                  style: TextStyle(
                    color: AppColors.textPrimary(context),
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Note field
          AppTextField(
            controller: noteCtrl,
            maxLines: 3,
            minLines: 1,
            style: TextStyle(
              color: AppColors.textPrimary(context),
              fontSize: 12,
            ),
            decoration: InputDecoration(
              hintText: "Author's note for ${c.name} (when they speak)...",
              hintStyle: TextStyle(
                color: AppColors.textTertiary(context),
                fontSize: 11,
              ),
              filled: true,
              fillColor: AppColors.surfaceContainerOf(context),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: AppColors.borderOf(context)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: AppColors.borderOf(context)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: Colors.purpleAccent),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 8,
              ),
            ),
            onChanged: (text) {
              widget.chatService.setAuthorNoteForGroupCharacter(c, text);
            },
          ),
          const SizedBox(height: 8),

          // Compact strength slider (1-10)
          Row(
            children: [
              Text(
                'Strength',
                style: TextStyle(
                  color: AppColors.textSecondary(context),
                  fontSize: 11,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 2.5,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 5,
                    ),
                    overlayShape: const RoundSliderOverlayShape(
                      overlayRadius: 10,
                    ),
                    activeTrackColor: _charColor(index),
                    inactiveTrackColor: AppColors.borderOf(context),
                    thumbColor: _charColor(index),
                  ),
                  child: Slider(
                    value: strength.toDouble(),
                    min: 1,
                    max: 10,
                    divisions: 9,
                    onChanged: (val) {
                      final newStrength = val.round();
                      rebuildState(() {
                        _perCharStrengths[c] = newStrength;
                      });
                      // Flush to service so it persists on Save / restart
                      final currentNote =
                          _perCharNoteControllers[c]?.text ?? '';
                      widget.chatService.setAuthorNoteForGroupCharacter(
                        c,
                        currentNote,
                        strength: newStrength,
                      );
                    },
                  ),
                ),
              ),
              SizedBox(
                width: 22,
                child: Text(
                  '$strength',
                  style: TextStyle(
                    color: _charColor(index),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCharacterSystemPromptEditor(CharacterCard c, int index) {
    final promptCtrl = _getOrCreateSystemPromptController(c);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.cardOf(context),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: avatar + name
          Row(
            children: [
              _memberAvatar(c, index),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  c.name,
                  style: TextStyle(
                    color: AppColors.textPrimary(context),
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton(
                onPressed: () {
                  promptCtrl.clear();
                  // A programmatic clear() never fires TextField.onChanged, so
                  // without this the box looked empty while the old override
                  // kept being injected every turn (and came back on reopen).
                  widget.chatService.setSystemPromptForGroupCharacter(c, '');
                },
                child: Text('Clear', style: TextStyle(fontSize: 11)),
              ),
            ],
          ),
          const SizedBox(height: 8),

          AppTextField(
            controller: promptCtrl,
            maxLines: 4,
            minLines: 2,
            style: TextStyle(
              color: AppColors.textPrimary(context),
              fontSize: 12,
            ),
            decoration: InputDecoration(
              hintText: 'Group-only system prompt for ${c.name}...',
              hintStyle: TextStyle(
                color: AppColors.textTertiary(context),
                fontSize: 11,
              ),
              filled: true,
              fillColor: AppColors.surfaceContainerOf(context),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: AppColors.borderOf(context)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: AppColors.borderOf(context)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: Colors.tealAccent),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 8,
              ),
            ),
            onChanged: (text) {
              widget.chatService.setSystemPromptForGroupCharacter(c, text);
            },
          ),
        ],
      ),
    );
  }
}
