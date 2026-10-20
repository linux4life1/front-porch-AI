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
import 'dart:ui' show BoxHeightStyle, BoxWidthStyle;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';
import 'package:front_porch_ai/services/services.dart'
    show DesktopSpellCheckService;

// Re-export so callers can reference SpellCheckConfiguration without an extra
// import when they need to explicitly opt out on a technical input field.
export 'package:flutter/material.dart' show SpellCheckConfiguration;

/// Interface for [TextEditingController] subclasses that provide their own
/// [SpellCheckResults] cache independently of Flutter's built-in spell check
/// pipeline (e.g. [StyledTextController] in the chat composer).
///
/// When a controller implements this interface,
/// [AppTextField.spellCheckContextMenuBuilder] reads suggestions from the
/// controller instead of from [EditableTextState.spellCheckResults], which
/// is null when [spellCheckConfiguration] is disabled.
abstract class SpellCheckResultsProvider {
  SpellCheckResults? get spellCheckResults;
}

/// The text a spell-check span covers in [text], or null when that span no
/// longer fits the string — an empty/invalid range, or one whose end is past
/// the end of the text. Every use of a [SuggestionSpan] range has to be
/// re-checked against the live text before it is read or replaced, because
/// spell-check results outlive the text they were measured against.
String? _spanWord(String text, TextRange range) {
  if (!range.isValid || range.isCollapsed) return null;
  if (range.start < 0 || range.end > text.length) return null;
  return text.substring(range.start, range.end);
}

/// The standard text input widget for all user-facing **prose** fields across
/// Front Porch AI (chat input, character descriptions, system prompts, lore
/// entries, story prose, etc.).
///
/// ## Why this wrapper exists
///
/// Flutter's [TextField] has platform-native spell check support via
/// [spellCheckConfiguration], but it is **disabled by default** on every
/// platform. There is no `ThemeData` hook for it, so the only maintainable
/// approach is a shared wrapper that enables it centrally.
///
/// ## Platform behaviour
///
/// | Platform | Spell check service            |
/// |----------|-------------------------------|
/// | macOS    | `NSSpellChecker`              |
/// | Windows  | Windows Spell Checking API    |
/// | Linux    | hunspell, compiled into the app             |
/// | iOS/Android | OS keyboard handles it (no override needed) |
///
/// This widget only injects [SpellCheckConfiguration] on the three desktop
/// platforms. All others fall through to Flutter's native defaults.
///
/// ## Opting out or customizing visuals (technical or stylized inputs)
///
/// API keys, URLs, host/port fields, model names, search bars, and other
/// non-prose inputs should remain as a plain [TextField] **or** pass
/// `spellCheckConfiguration: SpellCheckConfiguration.disabled()` explicitly.
///
/// For inputs that have their own custom `TextSpan` coloring (e.g. chat message
/// input "dialogue"/ *action* coloring) where the misspelled style would
/// otherwise interfere. The spell check service and suggestion results
/// remain active either way, so context menu corrections still work.
class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    this.controller,
    this.focusNode,
    this.undoController,
    this.decoration = const InputDecoration(),
    this.keyboardType,
    this.textInputAction,
    this.textCapitalization = TextCapitalization.none,
    this.style,
    this.strutStyle,
    this.textAlign = TextAlign.start,
    this.textAlignVertical,
    this.textDirection,
    this.readOnly = false,
    this.showCursor,
    this.autofocus = false,
    this.statesController,
    this.obscuringCharacter = '•',
    this.obscureText = false,
    this.autocorrect = true,
    this.smartDashesType,
    this.smartQuotesType,
    this.enableSuggestions = true,
    this.maxLines = 1,
    this.minLines,
    this.expands = false,
    this.maxLength,
    this.maxLengthEnforcement,
    this.onChanged,
    this.onEditingComplete,
    this.onSubmitted,
    this.onAppPrivateCommand,
    this.inputFormatters,
    this.enabled,
    this.ignorePointers,
    this.cursorWidth = 2.0,
    this.cursorHeight,
    this.cursorRadius,
    this.cursorOpacityAnimates,
    this.cursorColor,
    this.cursorErrorColor,
    this.selectionHeightStyle = BoxHeightStyle.tight,
    this.selectionWidthStyle = BoxWidthStyle.tight,
    this.keyboardAppearance,
    this.scrollPadding = const EdgeInsets.all(20.0),
    this.dragStartBehavior = DragStartBehavior.start,
    this.enableInteractiveSelection,
    this.selectionControls,
    this.onTap,
    this.onTapAlwaysCalled = false,
    this.onTapOutside,
    this.mouseCursor,
    this.buildCounter,
    this.scrollController,
    this.scrollPhysics,
    this.autofillHints = const <String>[],
    this.contentInsertionConfiguration,
    this.clipBehavior = Clip.hardEdge,
    this.restorationId,
    this.stylusHandwritingEnabled = true,
    this.enableIMEPersonalizedLearning = true,
    this.contextMenuBuilder,
    // Spell check configuration.
    //
    // Behaviours:
    //  - `null` (default) → platform default (enabled on Windows/macOS via
    //    [platformSpellCheck], disabled elsewhere).
    //  - `SpellCheckConfiguration.disabled()` → explicitly disabled.
    //
    // ⚠️ Do NOT pass `null` to disable spell check on Windows/macOS — it
    // will be silently upgraded to the platform default (enabled). Use
    // `SpellCheckConfiguration.disabled()` for explicit opt-out.
    this.spellCheckConfiguration,
    this.magnifierConfiguration,
    this.onTapUpOutside,
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final UndoHistoryController? undoController;
  final InputDecoration? decoration;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final TextCapitalization textCapitalization;
  final TextStyle? style;
  final StrutStyle? strutStyle;
  final TextAlign textAlign;
  final TextAlignVertical? textAlignVertical;
  final TextDirection? textDirection;
  final bool readOnly;
  final bool? showCursor;
  final bool autofocus;
  final WidgetStatesController? statesController;
  final String obscuringCharacter;
  final bool obscureText;
  final bool autocorrect;
  final SmartDashesType? smartDashesType;
  final SmartQuotesType? smartQuotesType;
  final bool enableSuggestions;
  final int? maxLines;
  final int? minLines;
  final bool expands;
  final int? maxLength;
  final MaxLengthEnforcement? maxLengthEnforcement;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onEditingComplete;
  final ValueChanged<String>? onSubmitted;
  final AppPrivateCommandCallback? onAppPrivateCommand;
  final List<TextInputFormatter>? inputFormatters;
  final bool? enabled;
  final bool? ignorePointers;
  final double cursorWidth;
  final double? cursorHeight;
  final Radius? cursorRadius;
  final bool? cursorOpacityAnimates;
  final Color? cursorColor;
  final Color? cursorErrorColor;
  final BoxHeightStyle selectionHeightStyle;
  final BoxWidthStyle selectionWidthStyle;
  final Brightness? keyboardAppearance;
  final EdgeInsets scrollPadding;
  final DragStartBehavior dragStartBehavior;
  final bool? enableInteractiveSelection;
  final TextSelectionControls? selectionControls;
  final GestureTapCallback? onTap;
  final bool onTapAlwaysCalled;
  final TapRegionCallback? onTapOutside;
  final MouseCursor? mouseCursor;
  final InputCounterWidgetBuilder? buildCounter;
  final ScrollController? scrollController;
  final ScrollPhysics? scrollPhysics;
  final Iterable<String>? autofillHints;
  final ContentInsertionConfiguration? contentInsertionConfiguration;
  final Clip clipBehavior;
  final String? restorationId;
  final bool stylusHandwritingEnabled;
  final bool enableIMEPersonalizedLearning;
  final EditableTextContextMenuBuilder? contextMenuBuilder;
  final SpellCheckConfiguration? spellCheckConfiguration;
  final TextMagnifierConfiguration? magnifierConfiguration;
  final TapRegionUpCallback? onTapUpOutside;

  /// Returns the correct [SpellCheckConfiguration] for the current platform,
  /// or `null` on unsupported platforms (web, mobile).
  ///
  /// Exposed as a static so other widgets that cannot use [AppTextField]
  /// (e.g. [TextFormField] with a `validator`) can reuse the same logic.
  ///
  /// ## macOS / Windows / Linux
  ///
  /// No explicit [SpellCheckService] is provided. On macOS, Flutter's material
  /// [TextField.build] routes the config through
  /// [CupertinoTextField.inferIOSSpellCheckConfiguration], which adds the
  /// misspelled text style and hands off to the native [FlutterTextInputPlugin]
  /// (NSSpellChecker). [DefaultSpellCheckService] must NOT be used here —
  /// its own documentation states it is "currently only supported by Android
  /// and iOS" and it returns empty results on macOS desktop.
  ///
  /// A debug-mode warning about `nativeSpellCheckServiceDefined` may appear
  /// on the first build before the text input plugin activates; this is a
  /// known Flutter timing quirk and does not prevent native spell check from
  /// working once a field is focused.
  ///
  /// | Platform | Behaviour                                        |
  /// |----------|--------------------------------------------------|
  /// | macOS    | Native NSSpellChecker via FlutterTextInputPlugin |
  /// | Windows  | Native Windows Spell Checking API                |
  /// | Linux    | Vendored hunspell + a bundled en_US dictionary   |
  /// | Others   | `null` — spell check disabled                   |
  ///
  /// Linux needs nothing installed: the engine is compiled into the binary and
  /// the dictionary ships in the app bundle. A user's own system dictionaries
  /// are preferred when present, which is what keeps other languages working;
  /// for a language with no dictionary anywhere the channel replies null and
  /// the field simply shows no underlines.
  ///
  /// [showMisspellings] controls whether the red wavy underline style is
  /// applied. Set to false for fields with custom TextSpan styling (e.g. chat
  /// input "dialogue"/ *action* coloring) where the misspelled style would
  /// otherwise interfere. The spell check service and suggestion results
  /// remain active either way, so context menu corrections still work.
  static SpellCheckConfiguration? platformSpellCheck({
    bool showMisspellings = true,
  }) {
    if (!DesktopSpellCheckService.isEnabled) return null;
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      return SpellCheckConfiguration(
        spellCheckService: DesktopSpellCheckService(),
        misspelledTextStyle: showMisspellings
            ? TextStyle(
                decoration: TextDecoration.underline,
                decorationColor: StatusColors.misspelling,
                decorationStyle: TextDecorationStyle.wavy,
              )
            : const TextStyle(), // no visual — preserves custom coloring
      );
    }
    return null;
  }

  /// Context menu builder that injects spell-check correction suggestions when
  /// the cursor is positioned on a misspelled word.
  ///
  /// Adds up to 5 replacement suggestions at the **top** of the right-click
  /// menu — above the standard Cut / Copy / Paste / Select All items.
  /// If the cursor is not on a misspelled word the standard menu is shown
  /// unchanged.
  ///
  /// Pass this as [contextMenuBuilder] on any [TextField] or [TextFormField]
  /// that also uses [platformSpellCheck] as its [spellCheckConfiguration].
  static Widget spellCheckContextMenuBuilder(
    BuildContext context,
    EditableTextState editableTextState,
  ) {
    // Allow custom controllers (e.g. StyledTextController) to provide their
    // own spell check cache when Flutter's built-in pipeline is disabled.
    final controller = editableTextState.widget.controller;
    final results = controller is SpellCheckResultsProvider
        ? (controller as SpellCheckResultsProvider).spellCheckResults
        : editableTextState.spellCheckResults;
    final TextEditingValue value = editableTextState.textEditingValue;

    // Find a misspelled span that contains the current cursor position.
    //
    // A span is only usable while the word it measured is still there: results
    // arrive asynchronously and are never invalidated when the text changes,
    // so a cached span can describe a longer, older string. Applying one
    // verbatim would rewrite the wrong characters — or throw, once its end is
    // past the end of the live text.
    SuggestionSpan? hitSpan;
    String? hitWord;
    if (results != null && value.selection.isValid) {
      final int cursor = value.selection.baseOffset;
      for (final SuggestionSpan span in results.suggestionSpans) {
        if (cursor < span.range.start || cursor > span.range.end) continue;
        final String? word = _spanWord(value.text, span.range);
        if (word == null) continue;
        hitSpan = span;
        hitWord = word;
        break;
      }
    }

    final List<ContextMenuButtonItem> baseItems =
        editableTextState.contextMenuButtonItems;

    if (hitSpan == null || hitSpan.suggestions.isEmpty) {
      // No misspelled word at cursor — return the standard context menu.
      return AdaptiveTextSelectionToolbar.buttonItems(
        anchors: editableTextState.contextMenuAnchors,
        buttonItems: baseItems,
      );
    }

    final SuggestionSpan span = hitSpan;
    final String word = hitWord!;
    final List<ContextMenuButtonItem> suggestionItems = span.suggestions
        .take(5)
        .map(
          (String suggestion) => ContextMenuButtonItem(
            label: suggestion,
            onPressed: () {
              // Read the LIVE value, not the one captured when the menu was
              // built: the field can be typed into, undone or programmatically
              // rewritten while the toolbar is open. If the misspelled word is
              // no longer sitting at that range, the correction no longer
              // applies — dropping it beats rewriting whatever moved in.
              final TextEditingValue current =
                  editableTextState.textEditingValue;
              if (_spanWord(current.text, span.range) == word) {
                editableTextState.userUpdateTextEditingValue(
                  current.replaced(span.range, suggestion),
                  SelectionChangedCause.tap,
                );
              }
              editableTextState.hideToolbar(false);
            },
          ),
        )
        .toList();

    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: editableTextState.contextMenuAnchors,
      buttonItems: <ContextMenuButtonItem>[...suggestionItems, ...baseItems],
    );
  }

  /// The resolved spell check configuration for this widget instance.
  ///
  /// Priority:
  ///   1. Explicit caller override (non-null) — allows both opt-in and opt-out
  ///   2. Platform-resolved default via [platformSpellCheck]
  ///   3. `null` — no spell check (unsupported platforms)
  ///
  /// **Note:** `null` from the caller does NOT disable spell check — it
  /// delegates to the platform default (enabled on Windows/macOS).
  /// Use `SpellCheckConfiguration.disabled()` to explicitly opt out.
  SpellCheckConfiguration? get _resolvedSpellCheck {
    // Explicit caller override always wins — allows both opt-in and opt-out.
    if (spellCheckConfiguration != null) return spellCheckConfiguration;
    // Never enable on obscured fields (passwords etc.)
    if (obscureText) return null;
    // Controllers that implement SpellCheckResultsProvider handle their own
    // custom spell check pipeline (e.g. StyledTextController), so disable
    // the built-in one to avoid conflicts in buildTextSpan().
    if (controller is SpellCheckResultsProvider) {
      return SpellCheckConfiguration.disabled();
    }
    return platformSpellCheck();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      undoController: undoController,
      decoration: decoration,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      textCapitalization: textCapitalization,
      style: style,
      strutStyle: strutStyle,
      textAlign: textAlign,
      textAlignVertical: textAlignVertical,
      textDirection: textDirection,
      readOnly: readOnly,
      showCursor: showCursor,
      autofocus: autofocus,
      statesController: statesController,
      obscuringCharacter: obscuringCharacter,
      obscureText: obscureText,
      autocorrect: autocorrect,
      smartDashesType: smartDashesType,
      smartQuotesType: smartQuotesType,
      enableSuggestions: enableSuggestions,
      maxLines: maxLines,
      minLines: minLines,
      expands: expands,
      maxLength: maxLength,
      maxLengthEnforcement: maxLengthEnforcement,
      onChanged: onChanged,
      onEditingComplete: onEditingComplete,
      onSubmitted: onSubmitted,
      onAppPrivateCommand: onAppPrivateCommand,
      inputFormatters: inputFormatters,
      enabled: enabled,
      ignorePointers: ignorePointers,
      cursorWidth: cursorWidth,
      cursorHeight: cursorHeight,
      cursorRadius: cursorRadius,
      cursorOpacityAnimates: cursorOpacityAnimates,
      cursorColor: cursorColor,
      cursorErrorColor: cursorErrorColor,
      selectionHeightStyle: selectionHeightStyle,
      selectionWidthStyle: selectionWidthStyle,
      keyboardAppearance: keyboardAppearance,
      scrollPadding: scrollPadding,
      dragStartBehavior: dragStartBehavior,
      enableInteractiveSelection: enableInteractiveSelection,
      selectionControls: selectionControls,
      onTap: onTap,
      onTapAlwaysCalled: onTapAlwaysCalled,
      onTapOutside: onTapOutside,
      mouseCursor: mouseCursor,
      buildCounter: buildCounter,
      scrollController: scrollController,
      scrollPhysics: scrollPhysics,
      autofillHints: autofillHints,
      contentInsertionConfiguration: contentInsertionConfiguration,
      clipBehavior: clipBehavior,
      restorationId: restorationId,
      stylusHandwritingEnabled: stylusHandwritingEnabled,
      enableIMEPersonalizedLearning: enableIMEPersonalizedLearning,
      contextMenuBuilder:
          contextMenuBuilder ?? AppTextField.spellCheckContextMenuBuilder,
      spellCheckConfiguration: _resolvedSpellCheck,
      magnifierConfiguration: magnifierConfiguration,
      onTapUpOutside: onTapUpOutside,
    );
  }
}
