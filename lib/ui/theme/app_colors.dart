// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  /// Surface background for dialogs, containers, and panels.
  static const Color surface = Color(0xFF1F2937);

  /// Deep background for scaffolds and page-level backgrounds.
  static const Color background = Color(0xFF0F172A);

  /// Card/container background for cards, dropdowns, and elevated surfaces.
  static const Color card = Color(0xFF1E293B);

  // ---------------------------------------------------------------------------
  // Chat appearance defaults
  // ---------------------------------------------------------------------------

  /// Default color for the user's message bubbles.
  static const Color userBubble = Color(0xFF3B82F6);

  /// Default color for the user's message text.
  static const Color userText = Colors.white;

  /// Default color for the AI's message bubbles.
  static const Color aiBubble = Color(0xFF374151);

  /// Default color for the AI's message text.
  static const Color aiText = Colors.white;

  /// Default color for quoted/dialogue text ("...").
  static const Color dialogue = Colors.amberAccent;

  /// Default color for action/emote text (*...*).
  static const Color action = Color(0xFF90CAF9);

  // ---------------------------------------------------------------------------
  // Light-mode backgrounds
  // ---------------------------------------------------------------------------

  /// Light-mode scaffold background (warmer paper tone for long-session comfort; chosen to eliminate glare).
  static const Color lightBackground = Color(0xFFF8F4ED);

  /// Light-mode card/container background.
  static const Color lightCard = Colors.white;

  /// Light-mode surface background for dialogs and panels (warmer paper tone).
  static const Color lightSurface = Color(0xFFF0EBE3);

  // ---------------------------------------------------------------------------
  // Container surface for dropdowns, dialogs, and input fields
  // ---------------------------------------------------------------------------

  /// Dark container surface (slightly lighter than [card] for visual layering).
  static const Color surfaceContainer = Color(0xFF374151);

  /// Light container surface for the same purpose (warmer paper tone).
  static const Color surfaceContainerLight = Color(0xFFEDE7DF);

  /// Subtle border color for cards/panels in light mode (defines shape without harsh contrast on paper bg).
  static const Color lightBorder = Color(0xFFD4CFC6);

  /// Brightness-aware container surface.
  static Color surfaceContainerOf(BuildContext context) =>
      resolve(context, surfaceContainer, surfaceContainerLight);

  // ---------------------------------------------------------------------------
  // Chat appearance defaults — light mode
  // ---------------------------------------------------------------------------

  /// Default user bubble color in light mode.
  static const Color userBubbleLight = Color(0xFF3B82F6);

  /// Default user text color in light mode.
  static const Color userTextLight = Colors.white;

  /// Default AI bubble color in light mode.
  static const Color aiBubbleLight = Color(0xFFE5E7EB);

  /// Default AI text color in light mode.
  static const Color aiTextLight = Colors.black87;

  /// Default dialogue color in light mode.
  static const Color dialogueLight = Color(0xFFB45309);

  /// Default action color in light mode.
  static const Color actionLight = Color(0xFF1565C0);

  // ---------------------------------------------------------------------------
  // Brightness-aware text/background helpers
  // ---------------------------------------------------------------------------

  /// True when the current brightness is light.
  static bool isLight(BuildContext context) =>
      Theme.of(context).brightness == Brightness.light;

  /// Primary text color for the current brightness.
  static Color textPrimary(BuildContext context) =>
      isLight(context) ? Colors.black87 : Colors.white;

  /// Secondary text color for the current brightness.
  static Color textSecondary(BuildContext context) =>
      isLight(context) ? Colors.black54 : Colors.white70;

  /// Tertiary text color for the current brightness.
  static Color textTertiary(BuildContext context) =>
      isLight(context) ? Colors.black45 : Colors.white38;

  /// Primary icon color (reuses exact isLight + ternary scaffold of textPrimary; no new logic).
  static Color iconPrimary(BuildContext context) =>
      isLight(context) ? Colors.black87 : Colors.white;

  /// Secondary / muted icon color (matches textSecondary pattern).
  static Color iconSecondary(BuildContext context) =>
      isLight(context) ? Colors.black54 : Colors.white70;

  /// Resolves a dark/light color pair based on current brightness.
  static Color resolve(BuildContext context, Color dark, Color light) =>
      isLight(context) ? light : dark;

  /// Background for the current brightness.
  static Color backgroundOf(BuildContext context) =>
      resolve(context, background, lightBackground);

  /// Card color for the current brightness.
  static Color cardOf(BuildContext context) =>
      resolve(context, card, lightCard);

  /// Surface color for the current brightness.
  static Color surfaceOf(BuildContext context) =>
      resolve(context, surface, lightSurface);

  /// Subtle border color for the current brightness (reuses resolve scaffold; no new logic).
  static Color borderOf(BuildContext context) =>
      resolve(context, const Color(0xFF334155), lightBorder);

  // ---------------------------------------------------------------------------
  // Process log / terminal output colors
  // ---------------------------------------------------------------------------

  /// Color for error/fail/fatal lines in process logs.
  static const Color logError = Color(0xFFFF6B6B);

  /// Color for warning lines in process logs.
  static const Color logWarn = Color(0xFFFFD93D);

  /// Color for ready/server-listen lines.
  static const Color logReady = Color(0xFF69F0AE);

  /// Color for loading/starting lines.
  static const Color logLoading = Color(0xFF93C5FD);

  /// Default color for normal lines.
  static const Color logDefault = Color(0xFF86EFAC);

  // ---------------------------------------------------------------------------
  // Creator wizard selected card backgrounds (for mode/backend chips)
  // Added for AppColors exclusive compliance in Stage 4 extraction.
  // ---------------------------------------------------------------------------

  /// Selected background for creator mode and backend selection cards.
  static const Color creatorSelectedCard = Color(0xFF1E3A5F);
  static const Color creatorSelectedCardLight = Color(0xFFE0F2FE);

  // ---------------------------------------------------------------------------
  // Preset palette for color pickers
  // ---------------------------------------------------------------------------

  /// Palette shown in color picker dialogs (no duplicates).
  static const List<Color> presetColors = [
    Color(0xFF3B82F6), // Blue
    Color(0xFF10B981), // Emerald
    Color(0xFFF59E0B), // Amber
    Color(0xFFEF4444), // Red
    Color(0xFF8B5CF6), // Purple
    Color(0xFFEC4899), // Pink
    Color(0xFF14B8A6), // Teal
    Color(0xFFF97316), // Orange
    Color(0xFF6366F1), // Indigo
    Color(0xFF06B6D4), // Cyan
    Color(0xFF84CC16), // Lime
  ];

  // ---------------------------------------------------------------------------
  // Realism form / optional accents (semantic for exclusive AppColors use in
  // refactored creator/edit/group surfaces incl. authority/verif toggles,
  // section headers, bond/trust/need sliders, master containers).
  // All literals confined here; UI code uses only AppColors.*Of / consts.
  // ---------------------------------------------------------------------------

  static const Color verifiedAccent = Color(0xFF009688);
  static const Color verifiedAccentLight = Color(0xFF009688);
  static Color verifiedAccentOf(BuildContext context) =>
      resolve(context, verifiedAccent, verifiedAccentLight);

  static const Color bondHigh = Colors.greenAccent;
  static const Color bondHighLight = Color(0xFF2E7D32);
  static Color bondHighOf(BuildContext context) =>
      resolve(context, bondHigh, bondHighLight);

  static const Color bondMid = Colors.blueAccent;
  static const Color bondMidLight = Color(0xFF1565C0);
  static Color bondMidOf(BuildContext context) =>
      resolve(context, bondMid, bondMidLight);

  static const Color bondLow = Colors.orangeAccent;
  static const Color bondLowLight = Color(0xFFE65100);
  static Color bondLowOf(BuildContext context) =>
      resolve(context, bondLow, bondLowLight);

  static const Color bondNeg = Colors.redAccent;
  static const Color bondNegLight = Color(0xFFC62828);
  static Color bondNegOf(BuildContext context) =>
      resolve(context, bondNeg, bondNegLight);

  static const Color trustHigh = Colors.tealAccent;
  static const Color trustHighLight = Color(0xFF00695C);
  static Color trustHighOf(BuildContext context) =>
      resolve(context, trustHigh, trustHighLight);

  /// Generic "primary accent" for forms, dialogs, Image Studio, and the
  /// avatar gallery (icons, badges, borders, primary buttons). Warm-porch:
  /// this is now porch amber (was Colors.blueAccent) so the ~30 files that key
  /// off it warm up in one place. It is a single const (not brightness-aware);
  /// on an amber button background use [onChaosAccent] for the foreground so
  /// text stays readable in dark mode (white-on-amber is too low-contrast).
  static const Color formMasterAccent = porchAmber;

  static const Color relationshipAccent = Colors.pinkAccent;
  static const Color relationshipAccentLight = Color(0xFFC2185B);
  static Color relationshipAccentOf(BuildContext context) =>
      resolve(context, relationshipAccent, relationshipAccentLight);

  static const Color emotionAccent = Colors.purpleAccent;
  static const Color emotionAccentLight = Color(0xFF7B1FA2);
  static Color emotionAccentOf(BuildContext context) =>
      resolve(context, emotionAccent, emotionAccentLight);

  static const Color optionalAccent = Colors.tealAccent;

  static const Color timeDayAccent = Colors.amberAccent;
  static const Color timeDayAccentLight = Color(0xFFB45309);
  static Color timeDayAccentOf(BuildContext context) =>
      resolve(context, timeDayAccent, timeDayAccentLight);

  static const Color taskAccent = Colors.orangeAccent;
  static const Color taskAccentLight = Color(0xFFC2410C);
  static Color taskAccentOf(BuildContext context) =>
      resolve(context, taskAccent, taskAccentLight);

  // ---------------------------------------------------------------------------
  // Warm-porch sidebar tokens (chat sidebar overhaul — one warm accent family
  // for section chrome, rose/ember for lust, one supporting cool tone for the
  // Journal/Memory cluster). Every former raw hex in the sidebar files maps to
  // exactly one token below; all have deliberate light variants.
  // ---------------------------------------------------------------------------

  /// 🎭 Character State section accent (warm terracotta).
  static const Color porchTerracotta = Color(0xFFE29578);
  static const Color porchTerracottaLight = Color(0xFF9C4B2F);
  static Color porchTerracottaOf(BuildContext context) =>
      resolve(context, porchTerracotta, porchTerracottaLight);

  /// 🎲 Story Tools section accent (warm honey).
  static const Color porchHoney = Color(0xFFE9C46A);
  static const Color porchHoneyLight = Color(0xFF8F6400);
  static Color porchHoneyOf(BuildContext context) =>
      resolve(context, porchHoney, porchHoneyLight);

  /// Generic warm accent for buttons/badges in the sidebar family.
  static const Color porchAmber = Color(0xFFF4A259);
  static const Color porchAmberLight = Color(0xFFB45309);
  static Color porchAmberOf(BuildContext context) =>
      resolve(context, porchAmber, porchAmberLight);

  /// 📖 Journal & Memory section accent — the recap, RAG, and evolution
  /// controls share this single supporting cool tone ("porch sage").
  static const Color journalAccent = Color(0xFF4DB6AC);
  static const Color journalAccentLight = Color(0xFF00796B);
  static Color journalAccentOf(BuildContext context) =>
      resolve(context, journalAccent, journalAccentLight);

  /// Lust bar / spicy toggles / NSFW headers (warm rose).
  static const Color lustAccent = Color(0xFFFB7185);
  static const Color lustAccentLight = Color(0xFFBE123C);
  static Color lustAccentOf(BuildContext context) =>
      resolve(context, lustAccent, lustAccentLight);

  /// Lust "fire" state (arousal tier >= 6).
  static const Color lustDeep = Color(0xFFF43F5E);
  static const Color lustDeepLight = Color(0xFF9F1239);
  static Color lustDeepOf(BuildContext context) =>
      resolve(context, lustDeep, lustDeepLight);

  /// Negative arousal / refractory chill.
  static const Color frostAccent = Color(0xFF38BDF8);
  static const Color frostAccentLight = Color(0xFF1D4ED8);
  static Color frostAccentOf(BuildContext context) =>
      resolve(context, frostAccent, frostAccentLight);

  /// Chaos Mode gold (switch, spin button).
  static const Color chaosAccent = Color(0xFFFFD166);
  static const Color chaosAccentLight = Color(0xFF9A6B15);
  static Color chaosAccentOf(BuildContext context) =>
      resolve(context, chaosAccent, chaosAccentLight);

  /// Spin-button gradient second stop.
  static const Color chaosAccentDim = Color(0xFFFFC233);
  static const Color chaosAccentDimLight = Color(0xFFB8860B);
  static Color chaosAccentDimOf(BuildContext context) =>
      resolve(context, chaosAccentDim, chaosAccentDimLight);

  /// Text/icon color on the chaos gold button (both modes).
  static const Color onChaosAccent = Color(0xFF1A1200);

  /// Chaos pressure-lerp start (calm) and end (hot).
  static const Color chaosCalm = Color(0xFF2EC4B6);
  static const Color chaosCalmLight = Color(0xFF0F766E);
  static Color chaosCalmOf(BuildContext context) =>
      resolve(context, chaosCalm, chaosCalmLight);
  static const Color chaosHot = Color(0xFFE63946);
  static const Color chaosHotLight = Color(0xFFB3261E);
  static Color chaosHotOf(BuildContext context) =>
      resolve(context, chaosHot, chaosHotLight);

  /// Positive trust bar/icon accent.
  static const Color trustAccent = Color(0xFFFFB300);
  static const Color trustAccentLight = Color(0xFFB45309);
  static Color trustAccentOf(BuildContext context) =>
      resolve(context, trustAccent, trustAccentLight);

  /// Negative trust/bond, critical needs, destructive hints.
  static const Color negativeAccent = Color(0xFFEF5350);
  static const Color negativeAccentLight = Color(0xFFD32F2F);
  static Color negativeAccentOf(BuildContext context) =>
      resolve(context, negativeAccent, negativeAccentLight);

  /// Fixation chip/banner purple (engine identity).
  static const Color fixationAccent = Color(0xFFE040FB);
  static const Color fixationAccentLight = Color(0xFF7B1FA2);
  static Color fixationAccentOf(BuildContext context) =>
      resolve(context, fixationAccent, fixationAccentLight);

  /// Inset wells (settings panels, sunken sub-surfaces). Light = warm paper.
  static const Color sunkenSurface = Color(0xFF111827);
  static const Color sunkenSurfaceLight = Color(0xFFE9E2D8);
  static Color sunkenSurfaceOf(BuildContext context) =>
      resolve(context, sunkenSurface, sunkenSurfaceLight);

  /// Read-only text wells (deepest inset, e.g. evolution "original" text).
  static const Color deepWell = Color(0xFF0D1117);
  static const Color deepWellLight = Color(0xFFF0EBE3);
  static Color deepWellOf(BuildContext context) =>
      resolve(context, deepWell, deepWellLight);

  // ── The Stoop "porch at dusk" palette ─────────────────────────────────
  // Dark values mirror hub.frontporchai.app's site.css tokens EXACTLY so the
  // in-app Stoop matches the web hub pixel-for-pixel; light values are the
  // warm-daylight derivation (maintainer decision 2026-07-30: adapt, don't
  // force dark). Semantics: amber = primary accent, teal = secondary
  // (links/tags/GROUP), ember = danger/NSFW, dusk = neutral info. The hub's
  // rule "no purple, ever" applies to all Stoop chrome.
  // Context helpers for these live in ui/pages/repository/stoop_glass.dart.

  /// Page backdrop (hub --bg-0) / warm paper.
  static const Color stoopBg0 = Color(0xFF0E0C09);
  static const Color stoopBg0Light = Color(0xFFFAF5EA);

  /// Inputs + inset wells (hub --bg-1).
  static const Color stoopBg1 = Color(0xFF14110D);
  static const Color stoopBg1Light = Color(0xFFF3ECDC);

  /// Card fill (hub --card) — gradient bottom stop.
  static const Color stoopCard = Color(0xFF191510);
  static const Color stoopCardLight = Color(0xFFFFFDF6);

  /// Card gradient top stop (hub --card-2).
  static const Color stoopCard2 = Color(0xFF201A13);
  static const Color stoopCard2Light = Color(0xFFF6EFDF);

  /// Hairline borders (hub --border / --border-hi).
  static const Color stoopBorder = Color(0xFF2C251B);
  static const Color stoopBorderLight = Color(0xFFE3D9C1);
  static const Color stoopBorderHi = Color(0xFF3F3522);
  static const Color stoopBorderHiLight = Color(0xFFCFC2A2);

  /// Text ramp (hub --cream / --cream-2 / --mute / --faint).
  static const Color stoopCream = Color(0xFFF3ECDD);
  static const Color stoopCreamLight = Color(0xFF2E2718);
  static const Color stoopCream2 = Color(0xFFCFC5B0);
  static const Color stoopCream2Light = Color(0xFF5C5340);
  static const Color stoopMute = Color(0xFF9A8F76);
  static const Color stoopMuteLight = Color(0xFF86795C);
  static const Color stoopFaint = Color(0xFF6E654F);
  static const Color stoopFaintLight = Color(0xFFA89C7F);

  /// Amber lamplight (hub --amber / --amber-hi / --amber-deep). Fills use the
  /// const hi→base gradient with [stoopAmberInk] text in BOTH modes; amber as
  /// TEXT uses the Of pair below for contrast on light paper.
  static const Color stoopAmber = Color(0xFFF5A623);
  static const Color stoopAmberHi = Color(0xFFFFC44D);
  static const Color stoopAmberDeep = Color(0xFFC97F16);
  static const Color stoopAmberTextLight = Color(0xFFA9690C);

  /// Near-black ink on amber/ember gradient fills (hub #241502).
  static const Color stoopAmberInk = Color(0xFF241502);

  /// Ember — danger + NSFW (hub --ember; text variant #ffb08a).
  static const Color stoopEmber = Color(0xFFE8833A);
  static const Color stoopEmberText = Color(0xFFFFB08A);
  static const Color stoopEmberTextLight = Color(0xFFB54E10);

  /// Teal — secondary accent (hub --teal / --teal-hi).
  static const Color stoopTeal = Color(0xFF4CB8A4);
  static const Color stoopTealText = Color(0xFF74D6C2);
  static const Color stoopTealTextLight = Color(0xFF1F7A67);

  /// Dusk blue — neutral info accent (hub --dusk).
  static const Color stoopDusk = Color(0xFF5F9EC7);
  static const Color stoopDuskLight = Color(0xFF3E749B);

  /// Stoop owner check fill. Hub `.hub-check-gold` / Twitter-X gold `#e8b923`.
  static const Color stoopCheckGold = Color(0xFFE8B923);

  /// Trusted-uploader check (hub `#1d9bf0`). Semantic, not chrome.
  static const Color stoopCheckBlue = Color(
    0xFF1D9BF0,
  ); // theme-keep: hub verification blue
}
