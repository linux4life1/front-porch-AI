// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

/// The user-facing Acceptable Use Policy for The Stoop (the community character
/// hub). This is the bundled text shown in the in-app gate; the *live* version
/// string is owned by the server (`policyVersion`) — when the server's version
/// moves past what a user accepted, the gate is shown again. Keep [kStoopAupId]
/// in step with the server's `POLICY_VERSION` whenever this text changes.
library;

/// The policy revision this bundled text corresponds to. Shown to the user for
/// reference; acceptance is recorded against the server's live version.
const String kStoopAupId = '1.3';

/// One titled block of the policy, rendered as a header + body paragraph(s).
class StoopPolicySection {
  final String title;
  final String body;
  const StoopPolicySection(this.title, this.body);
}

const String kStoopAupIntro =
    'The Stoop is a community hub for sharing AI character cards, built into '
    'Front Porch. It is strictly for adults (18+). Please read this before you '
    'come in — by agreeing, you accept the terms below. You can use everything '
    'else in Front Porch without an account; this only covers The Stoop.';

const List<StoopPolicySection> kStoopAupSections = [
  StoopPolicySection(
    'The basics',
    'You must be 18 or older. One person, one account. Characters you upload '
        'stay yours — you just grant permission to host and share them on The '
        'Stoop, and you can remove them at any time. Everything uploaded is '
        'reviewed before it goes public, and a card may be rejected or removed '
        'at a moderator’s discretion.',
  ),
  StoopPolicySection(
    'What’s allowed — and what isn’t',
    'Adult (18+) fictional content, including NSFW, is welcome. With that '
        'freedom come hard limits. Absolutely prohibited, with zero tolerance: '
        'any sexual content involving minors — including fictional characters '
        'described, drawn, implied, or “aged-up” to look underage; '
        'non-consensual sexual content involving real people; content promoting '
        'real-world violence or illegal acts; and sharing anyone’s private '
        'information. Mark NSFW cards as NSFW — mislabeling to dodge filters is '
        'a violation. Imagery is held to a stricter line than text: avatars and '
        'card images must stay non-pornographic — no nudity, bare bodies, sex '
        'acts, or images whose purpose is to induce lust. Clothed or merely '
        'suggestive art is fine; explicit nude imagery is not allowed even on '
        'cards marked NSFW.',
  ),
  StoopPolicySection(
    'Characters with a will of their own',
    'Cards on The Stoop should be written as autonomous beings — believable '
        'and capable of their own choices — not scripts that force a single '
        'predetermined outcome. Forced harems, pre-scripted or forced weddings, '
        'and “must obey” characters with no agency will be rejected. '
        'This is about how a card is written, not how you play it: if you keep '
        'interacting with a character, that’s your choice. The rule '
        'protects the believability of the characters, not the player.',
  ),
  StoopPolicySection(
    'Cards worth sharing',
    'A card should earn its place on the porch. It should be substantial — more '
        'than a bare prompt, with a real scenario, example dialogue, or '
        'supporting detail; coherent — persona, scenario, and content agree, '
        'with no contradictions; and readable — understandable writing and '
        'formatting, unless it’s an intentionally structured JSON/code card. '
        'Low-effort or “slop” cards that add nothing beyond a one-line prompt '
        'may be rejected or removed.',
  ),
  StoopPolicySection(
    'Credit where credit’s due',
    'Upload your own work. Sharing a character someone else made (or a close '
        'derivative of one) is allowed only with proper attribution: fill in '
        'the “Original creator” field when you upload, so the card shows who '
        'actually made it — the original creator doesn’t need a Stoop account '
        'to be credited. Reposting someone else’s card without that credit is '
        'a warnable offense: each incident earns a formal warning in your '
        'inbox, and three warnings result in a ban. Deliberately passing '
        'someone else’s work off as your own can be an immediate ban. '
        'Submissions are checked against the well-known character '
        'repositories, and uncredited matches are held for a human moderator '
        'to review.',
  ),
  StoopPolicySection(
    'Your data & privacy',
    'We store your email, age confirmation, and account activity (uploads, '
        'votes, downloads). For security and to enforce bans we also keep a '
        'one-way salted hash of your IP address (never the raw address) and an '
        'anonymous per-install id. This security data is a required condition of '
        'having a Stoop account and cannot be turned off — if you don’t '
        'want it collected, don’t create an account; the rest of Front '
        'Porch still works fully. It is automatically deleted after 90 days. '
        'NSFW content is hidden by default until you turn it on. Optional device '
        'info (your platform/OS/GPU) helps improve the app and can be turned off '
        'in Settings with no loss of features.',
  ),
  StoopPolicySection(
    'Bans & ban evasion',
    'A ban applies to the person, not just the account. Creating a new account '
        'to get around a ban is itself a bannable offense — a banned device is '
        'blocked from signing up again, and a new account that shares signals '
        'with a banned one may be flagged for a human to review. We don’t '
        'auto-ban solely because two people share an internet connection.',
  ),
  StoopPolicySection(
    'Vote and report honestly — no brigading',
    'Votes and reports are for your own honest opinion of a card. Brigading — '
        'organising or joining a group to pile votes or reports on a card to '
        'artificially bury or boost it — is a bannable offense. For example: '
        'rallying people in a Discord, group chat, or community to mass-downvote '
        'a creator you dislike (or mass-upvote your own cards); mass-reporting a '
        'card that doesn’t actually break these rules in order to get it taken '
        'down; or using more than one account to vote or report on the same '
        'card. Moderators can see who voted and who reported, and act on '
        'coordinated patterns — not on honest disagreement, which is always '
        'fine.',
  ),
  StoopPolicySection(
    'Reporting, takedowns & appeals',
    'Every card has a Report button — use it for anything that breaks these '
        'rules. Copyright / DMCA takedown requests are handled by opening an '
        'issue on the Front Porch GitHub repository. If a moderator removes or '
        'rejects something of yours, you’ll get a message in the app '
        'explaining why, and you can reply there; the community Discord is also '
        'open for questions.',
  ),
  StoopPolicySection(
    'Deleting your account',
    'You can permanently delete your Stoop account at any time from inside the '
        'app. This erases your account, your uploaded characters, your votes, '
        'and your messages. Copies other people already downloaded to their own '
        'devices are beyond our control.',
  ),
];
