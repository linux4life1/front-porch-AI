// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/providers/auth_state.dart';
import 'package:front_porch_ai/services/backporch/backporch.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Opt-in two-factor (TOTP) management for a Stoop account. Opens the enrollment
/// flow when 2FA is off (QR + secret + confirm a code), or the turn-off flow
/// when it's on (confirm a current code). Reachable any time from the account
/// sheet — never a hard gate.
Future<void> showStoopTwoFactor(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.cardOf(context),
    showDragHandle: true,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => const _TwoFactorSheet(),
  );
}

class _TwoFactorSheet extends StatefulWidget {
  const _TwoFactorSheet();

  @override
  State<_TwoFactorSheet> createState() => _TwoFactorSheetState();
}

class _TwoFactorSheetState extends State<_TwoFactorSheet> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  // Enrollment material (only loaded when turning 2FA on).
  ({String secret, String otpauthUrl, String qrDataUrl})? _setup;
  bool _loadingSetup = false;

  @override
  void initState() {
    super.initState();
    final enabled = context.read<AuthState>().user?.twoFactorEnabled ?? false;
    if (!enabled) _loadSetup();
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _loadSetup() async {
    setState(() {
      _loadingSetup = true;
      _error = null;
    });
    try {
      final s = await context.read<AuthState>().setupTwoFactor();
      if (mounted) setState(() => _setup = s);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Couldn’t start setup. Check your connection.');
      }
    } finally {
      if (mounted) setState(() => _loadingSetup = false);
    }
  }

  Future<void> _submit({required bool enabling}) async {
    final code = _code.text.trim();
    if (code.length < 6) {
      setState(() => _error = 'Enter the 6-digit code.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final auth = context.read<AuthState>();
    try {
      if (enabling) {
        await auth.enableTwoFactor(code);
      } else {
        await auth.disableTwoFactor(code);
      }
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            enabling
                ? 'Two-factor authentication is on. You’ll enter a code at sign-in.'
                : 'Two-factor authentication is off.',
          ),
        ),
      );
    } on BackporchApiException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.code == 'invalid_code'
              ? 'That code didn’t match. Try again.'
              : 'Couldn’t update 2FA. Try again.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Couldn’t update 2FA. Check your connection.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = context.watch<AuthState>().user?.twoFactorEnabled ?? false;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          4,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: enabled ? _disableBody() : _enableBody(),
          ),
        ),
      ),
    );
  }

  // ---- turn ON (enrollment) ----
  List<Widget> _enableBody() {
    final setup = _setup;
    return [
      _title('Protect your account'),
      _subtitle(
        'Add an authenticator app (Google Authenticator, Authy, 1Password…). '
        'Scan the code or enter the key, then confirm a 6-digit code.',
      ),
      const SizedBox(height: 16),
      if (_loadingSetup || setup == null)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 32),
          child: Center(child: CircularProgressIndicator()),
        )
      else ...[
        Center(child: _qr(setup.qrDataUrl)),
        const SizedBox(height: 14),
        _secretRow(setup.secret),
        const SizedBox(height: 16),
        _codeField(),
        if (_error != null) _errorText(),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _busy ? null : () => _submit(enabling: true),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          child: _busy ? _spinner() : const Text('Turn on 2FA'),
        ),
      ],
    ];
  }

  // ---- turn OFF ----
  List<Widget> _disableBody() {
    return [
      _title('Two-factor is on'),
      _subtitle(
        'Your account asks for an authenticator code at sign-in. To turn it '
        'off, enter a current code.',
      ),
      const SizedBox(height: 16),
      _codeField(),
      if (_error != null) _errorText(),
      const SizedBox(height: 16),
      FilledButton(
        onPressed: _busy ? null : () => _submit(enabling: false),
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.resolve(
            context,
            Colors.red.shade600,
            Colors.red.shade700,
          ),
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        child: _busy ? _spinner() : const Text('Turn off 2FA'),
      ),
    ];
  }

  Widget _qr(String dataUrl) {
    try {
      final bytes = base64Decode(dataUrl.split(',').last);
      return Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white, // QR needs a light quiet-zone to scan reliably
          borderRadius: BorderRadius.circular(12),
        ),
        child: Image.memory(bytes, width: 180, height: 180, gaplessPlayback: true),
      );
    } catch (_) {
      return const SizedBox.shrink();
    }
  }

  Widget _secretRow(String secret) {
    return Row(
      children: [
        Expanded(
          child: SelectableText(
            secret,
            style: TextStyle(
              color: AppColors.textSecondary(context),
              fontFamily: 'monospace',
              fontSize: 13,
              letterSpacing: 1,
            ),
          ),
        ),
        IconButton(
          tooltip: 'Copy key',
          icon: Icon(
            Icons.copy_rounded,
            size: 18,
            color: AppColors.iconSecondary(context),
          ),
          onPressed: () {
            Clipboard.setData(ClipboardData(text: secret));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Setup key copied.')),
            );
          },
        ),
      ],
    );
  }

  Widget _codeField() {
    return TextField(
      controller: _code,
      enabled: !_busy,
      keyboardType: TextInputType.number,
      maxLength: 8,
      style: TextStyle(color: AppColors.textPrimary(context), letterSpacing: 4),
      decoration: InputDecoration(
        counterText: '',
        hintText: '123456',
        hintStyle: TextStyle(color: AppColors.textTertiary(context)),
        filled: true,
        fillColor: AppColors.surfaceContainerOf(context),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: AppColors.borderOf(context)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: AppColors.borderOf(context)),
        ),
      ),
    );
  }

  Widget _title(String t) => Text(
    t,
    style: TextStyle(
      color: AppColors.textPrimary(context),
      fontWeight: FontWeight.bold,
      fontSize: 18,
    ),
  );

  Widget _subtitle(String t) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Text(
      t,
      style: TextStyle(color: AppColors.textSecondary(context), height: 1.4),
    ),
  );

  Widget _errorText() => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: Text(
      _error!,
      style: TextStyle(
        color: AppColors.resolve(context, Colors.redAccent, Colors.red.shade700),
        fontSize: 13,
      ),
    ),
  );

  Widget _spinner() => const SizedBox(
    width: 18,
    height: 18,
    child: CircularProgressIndicator(strokeWidth: 2),
  );
}
