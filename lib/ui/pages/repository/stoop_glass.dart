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
// The Stoop design core — "porch at dusk", matching hub.frontporchai.app.
// Every Stoop surface styles itself through these tokens and building blocks
// (palette constants live in AppColors, `stoop*` block): warm brown-black
// surfaces, amber lamplight, teal secondary, cream text, serif display
// headings. Amber = primary, teal = tags/links/GROUP, ember = danger/NSFW.
// No purple, ever (hub rule). Light mode is the warm-daylight derivation.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:front_porch_ai/services/macro_resolver.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

final MacroResolver _stoopMacros = MacroResolver();

/// Resolve `{{char}}` → the character's name (and `{{user}}` → "You") for any
/// card text shown in The Stoop, using the app's shared macro resolver so it
/// matches how definitions render in chat.
String stoopResolveMacros(String text, String charName) {
  if (text.isEmpty || !text.contains('{')) return text;
  return _stoopMacros.resolve(
    text,
    MacroContext(userName: 'You', characterName: charName),
  );
}

/// Compact label for a card's token count — `620` or `1.2k` (drops a trailing
/// `.0`). Returns null for a null/zero count so callers can hide the chip
/// (older records may not be backfilled yet).
String? stoopTokenLabel(int? tokens) {
  if (tokens == null || tokens <= 0) return null;
  if (tokens < 1000) return '$tokens';
  final s = (tokens / 1000).toStringAsFixed(1);
  return '${s.endsWith('.0') ? s.substring(0, s.length - 2) : s}k';
}

// ── Surface tokens ───────────────────────────────────────────────────────

Color stoopBg0(BuildContext c) =>
    AppColors.resolve(c, AppColors.stoopBg0, AppColors.stoopBg0Light);
Color stoopBg1(BuildContext c) =>
    AppColors.resolve(c, AppColors.stoopBg1, AppColors.stoopBg1Light);
Color stoopCard(BuildContext c) =>
    AppColors.resolve(c, AppColors.stoopCard, AppColors.stoopCardLight);
Color stoopCard2(BuildContext c) =>
    AppColors.resolve(c, AppColors.stoopCard2, AppColors.stoopCard2Light);
Color stoopBorder(BuildContext c) =>
    AppColors.resolve(c, AppColors.stoopBorder, AppColors.stoopBorderLight);
Color stoopBorderHi(BuildContext c) =>
    AppColors.resolve(c, AppColors.stoopBorderHi, AppColors.stoopBorderHiLight);

// ── Text ramp ────────────────────────────────────────────────────────────

Color stoopCream(BuildContext c) =>
    AppColors.resolve(c, AppColors.stoopCream, AppColors.stoopCreamLight);
Color stoopCream2(BuildContext c) =>
    AppColors.resolve(c, AppColors.stoopCream2, AppColors.stoopCream2Light);
Color stoopMute(BuildContext c) =>
    AppColors.resolve(c, AppColors.stoopMute, AppColors.stoopMuteLight);
Color stoopFaint(BuildContext c) =>
    AppColors.resolve(c, AppColors.stoopFaint, AppColors.stoopFaintLight);

// ── Accents ──────────────────────────────────────────────────────────────

/// Amber used AS TEXT (bright on dusk, deep on paper).
Color stoopAmberText(BuildContext c) =>
    AppColors.resolve(c, AppColors.stoopAmberHi, AppColors.stoopAmberTextLight);

Color stoopEmberText(BuildContext c) => AppColors.resolve(
  c,
  AppColors.stoopEmberText,
  AppColors.stoopEmberTextLight,
);

Color stoopTealText(BuildContext c) =>
    AppColors.resolve(c, AppColors.stoopTealText, AppColors.stoopTealTextLight);

Color stoopDusk(BuildContext c) =>
    AppColors.resolve(c, AppColors.stoopDusk, AppColors.stoopDuskLight);

/// Soft accent washes (hub --amber-soft / --teal-soft) — alpha overlays that
/// read correctly on both dusk and paper.
Color stoopAmberSoft(BuildContext c) =>
    AppColors.stoopAmber.withValues(alpha: 0.12);
Color stoopTealSoft(BuildContext c) =>
    AppColors.stoopTeal.withValues(alpha: 0.12);

/// The lamplight CTA fill (hub buttons, .on chips, PICK badge). Constant in
/// both modes — always carries [AppColors.stoopAmberInk] text.
const LinearGradient stoopAmberGradient = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [AppColors.stoopAmberHi, AppColors.stoopAmber],
);

/// The ember fill (danger buttons, downvote-on).
const LinearGradient stoopEmberGradient = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [Color(0xFFF0925A), AppColors.stoopEmber],
);

/// Card face (hub: linear-gradient(180deg, --card-2, --card)).
LinearGradient stoopCardGradient(BuildContext c) => LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [stoopCard2(c), stoopCard(c)],
);

// ── Type ─────────────────────────────────────────────────────────────────

/// Serif display style (hub --font-display: Fraunces) for headings and card
/// names. google_fonts is the app's established pattern (chat fonts).
TextStyle stoopDisplay(
  BuildContext c, {
  double size = 20,
  FontWeight weight = FontWeight.w600,
  Color? color,
}) => GoogleFonts.fraunces(
  fontSize: size,
  fontWeight: weight,
  letterSpacing: -0.3,
  height: 1.16,
  color: color ?? stoopCream(c),
);

// ── Building blocks ──────────────────────────────────────────────────────

/// Card/panel face: gradient fill, hairline border, resting shadow
/// (hub .hub-tile / .hub-modal / .hub-acct-sect).
BoxDecoration stoopPanel(
  BuildContext c, {
  double radius = 14,
  bool hi = false,
}) => BoxDecoration(
  gradient: stoopCardGradient(c),
  borderRadius: BorderRadius.circular(radius),
  border: Border.all(color: hi ? stoopBorderHi(c) : stoopBorder(c)),
  boxShadow: const [
    BoxShadow(color: Color(0x59000000), blurRadius: 30, offset: Offset(0, 10)),
  ],
);

/// Text field chrome (hub inputs: bg-1 fill, border-hi, amber focus ring).
InputDecoration stoopInput(
  BuildContext c,
  String hint, {
  Widget? prefixIcon,
  Widget? suffixIcon,
  String? counterText,
}) {
  OutlineInputBorder line(Color color, [double w = 1]) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(9),
    borderSide: BorderSide(color: color, width: w),
  );
  return InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(color: stoopFaint(c)),
    prefixIcon: prefixIcon,
    suffixIcon: suffixIcon,
    counterText: counterText,
    filled: true,
    fillColor: stoopBg1(c),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    border: line(stoopBorderHi(c)),
    enabledBorder: line(stoopBorderHi(c)),
    focusedBorder: line(AppColors.stoopAmberDeep, 1.4),
  );
}

/// The uppercase mini-badges on card art (hub .hub-badge): PICK on the amber
/// gradient with dark ink; GROUP teal, WORLD amber, CLIMATE teal, LORE cream,
/// NSFW ember — each tinted text on a deep translucent ground with a matching
/// hairline.
enum StoopBadgeKind { pick, featured, group, world, climate, lore, nsfw }

/// WORLD plus CLIMATE or LORE. Same pill chrome as GROUP/WORLD.
List<Widget> stoopWorldKindBadges({required bool climateEnabled}) => [
  const StoopBadge(StoopBadgeKind.world),
  StoopBadge(climateEnabled ? StoopBadgeKind.climate : StoopBadgeKind.lore),
];

class StoopBadge extends StatelessWidget {
  final StoopBadgeKind kind;
  const StoopBadge(this.kind, {super.key});

  @override
  Widget build(BuildContext context) {
    final (label, fg, bg, borderColor, gradient) = switch (kind) {
      StoopBadgeKind.pick => (
        '★ PICK',
        AppColors.stoopAmberInk,
        null,
        null,
        stoopAmberGradient,
      ),
      StoopBadgeKind.featured => (
        '✦ FEATURED',
        AppColors.stoopAmberInk,
        null,
        null,
        stoopAmberGradient,
      ),
      StoopBadgeKind.group => (
        'GROUP',
        AppColors.stoopTealText,
        const Color(0xBF06201B),
        AppColors.stoopTeal.withValues(alpha: 0.45),
        null,
      ),
      StoopBadgeKind.world => (
        'WORLD',
        AppColors.stoopAmberHi,
        const Color(0xBF241502),
        AppColors.stoopAmber.withValues(alpha: 0.45),
        null,
      ),
      StoopBadgeKind.climate => (
        'CLIMATE',
        AppColors.stoopTealText,
        const Color(0xBF06201B),
        AppColors.stoopTeal.withValues(alpha: 0.45),
        null,
      ),
      StoopBadgeKind.lore => (
        'LORE',
        AppColors.stoopCream,
        const Color(0xBF1A1610),
        AppColors.stoopBorderHi.withValues(alpha: 0.8),
        null,
      ),
      StoopBadgeKind.nsfw => (
        'NSFW',
        AppColors.stoopEmberText,
        const Color(0xBF2A0F04),
        AppColors.stoopEmber.withValues(alpha: 0.5),
        null,
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        gradient: gradient,
        borderRadius: BorderRadius.circular(999),
        border: borderColor != null ? Border.all(color: borderColor) : null,
      ),
      child: Text(
        label,
        style: TextStyle(
          color: fg,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

/// The lamplight CTA (hub primary button): amber gradient, dark ink, subtle
/// glow. `busy` swaps the label for a small spinner and disables the tap.
class StoopAmberButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool busy;
  final EdgeInsetsGeometry padding;
  const StoopAmberButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.busy = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !busy;
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: stoopAmberGradient,
          borderRadius: BorderRadius.circular(9),
          boxShadow: enabled
              ? [
                  BoxShadow(
                    color: AppColors.stoopAmber.withValues(alpha: 0.25),
                    blurRadius: 18,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(9),
            onTap: enabled ? onPressed : null,
            child: Padding(
              padding: padding,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (busy)
                    const SizedBox(
                      width: 15,
                      height: 15,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.stoopAmberInk,
                      ),
                    )
                  else if (icon != null)
                    Icon(icon, size: 17, color: AppColors.stoopAmberInk),
                  if (busy || icon != null) const SizedBox(width: 7),
                  Text(
                    label,
                    style: const TextStyle(
                      color: AppColors.stoopAmberInk,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The hub's loading "lamp": a pulsing amber dot with a warm glow — The
/// Stoop's replacement for a bare spinner.
class StoopLamp extends StatefulWidget {
  final String? caption;
  const StoopLamp({super.key, this.caption});

  @override
  State<StoopLamp> createState() => _StoopLampState();
}

class _StoopLampState extends State<StoopLamp>
    with SingleTickerProviderStateMixin {
  late final AnimationController _t = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _t,
            builder: (context, _) {
              final v = Curves.easeInOut.transform(_t.value);
              return Opacity(
                opacity: 0.45 + 0.55 * v,
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.stoopAmberHi,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.stoopAmber.withValues(
                          alpha: 0.25 + 0.3 * v,
                        ),
                        blurRadius: 18,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          if (widget.caption != null) ...[
            const SizedBox(height: 16),
            Text(widget.caption!, style: TextStyle(color: stoopMute(context))),
          ],
        ],
      ),
    );
  }
}

/// Hub empty state: a big glyph, a cream-2 title, muted body, optional action.
Widget stoopEmpty(
  BuildContext context, {
  required String glyph,
  required String title,
  String? body,
  Widget? action,
}) {
  return Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 54),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(glyph, style: const TextStyle(fontSize: 34)),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: stoopCream2(context),
              fontWeight: FontWeight.w600,
              fontSize: 16,
            ),
          ),
          if (body != null) ...[
            const SizedBox(height: 6),
            Text(
              body,
              textAlign: TextAlign.center,
              style: TextStyle(color: stoopMute(context), height: 1.5),
            ),
          ],
          if (action != null) ...[const SizedBox(height: 16), action],
        ],
      ),
    ),
  );
}
