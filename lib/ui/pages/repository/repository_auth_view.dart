// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/providers/auth_state.dart';
import 'package:front_porch_ai/services/backporch/backporch.dart';
import 'package:front_porch_ai/ui/pages/repository/stoop_glass.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// The login / create-account gate shown when no repository account is signed
/// in. On success, [AuthState] flips to logged-in and the parent page swaps
/// this out for the repository itself.
class RepositoryAuthView extends StatefulWidget {
  const RepositoryAuthView({super.key});

  @override
  State<RepositoryAuthView> createState() => _RepositoryAuthViewState();
}

class _RepositoryAuthViewState extends State<RepositoryAuthView> {
  bool _isSignup = false;
  bool _busy = false;
  bool _twoFactorRequired = false; // reveal the authenticator-code field
  String? _error;
  DateTime? _dob;

  final _email = TextEditingController();
  final _password = TextEditingController();
  final _displayName = TextEditingController();
  final _totp = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _displayName.dispose();
    _totp.dispose();
    super.dispose();
  }

  int _ageInYears(DateTime dob) {
    final now = DateTime.now();
    var age = now.year - dob.year;
    if (now.month < dob.month ||
        (now.month == dob.month && now.day < dob.day)) {
      age--;
    }
    return age;
  }

  String _mapError(String code) {
    switch (code) {
      case 'invalid_credentials':
        return 'Incorrect email or password.';
      case 'email_taken':
        return 'That email is already registered. Try signing in.';
      case 'disposable_email':
        return 'Please use a permanent email address — throwaway addresses '
            "aren't accepted. You can browse The Stoop without an account.";
      case 'undeliverable_email':
        return "That domain can't receive email. Check the address and try "
            'again.';
      case 'underage':
        return 'You must be 18 or older to use The Stoop.';
      case 'account_banned':
        return 'This account has been suspended.';
      case 'invalid_input':
        return 'Please double-check your details.';
      default:
        return 'Something went wrong. Check your connection and try again.';
    }
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    final email = _email.text.trim();
    final pass = _password.text;
    if (!email.contains('@') || email.length < 3) {
      setState(() => _error = 'Enter a valid email address.');
      return;
    }
    if (pass.length < 8) {
      setState(() => _error = 'Password must be at least 8 characters.');
      return;
    }
    if (_isSignup) {
      if (_displayName.text.trim().isEmpty) {
        setState(() => _error = 'Choose a display name.');
        return;
      }
      if (_dob == null) {
        setState(() => _error = 'Select your date of birth.');
        return;
      }
      if (_ageInYears(_dob!) < 18) {
        setState(() => _error = 'You must be 18 or older to use The Stoop.');
        return;
      }
    }

    setState(() => _busy = true);
    final auth = Provider.of<AuthState>(context, listen: false);
    try {
      if (_isSignup) {
        await auth.signup(
          email: email,
          password: pass,
          displayName: _displayName.text,
          dateOfBirth: _dob!,
        );
      } else {
        await auth.login(
          email: email,
          password: pass,
          totp: _twoFactorRequired ? _totp.text.trim() : null,
        );
      }
      // Success: AuthState notifies and the parent swaps this view out.
    } on BackporchApiException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          if (e.code == 'two_factor_required') {
            // The server asks for a code: reveal the field the first time, then
            // treat a repeat as a wrong/expired code (same error either way).
            _error = _twoFactorRequired
                ? 'That code didn’t match. Try again.'
                : 'Enter the 6-digit code from your authenticator app.';
            _twoFactorRequired = true;
          } else {
            _error = _mapError(e.code);
          }
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Something went wrong. Check your connection and try again.';
          _busy = false;
        });
      }
    }
  }

  // Ask the server for a reset email. The emailed link opens the hub's reset
  // page in a browser (email links can't land inside the app); once the new
  // password is set, signing in here works again. The server never reveals
  // whether an address has an account.
  Future<void> _forgotPassword() async {
    final controller = TextEditingController(text: _email.text.trim());
    final sent = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: stoopCard2(ctx),
        title: Text('Locked out?', style: TextStyle(color: stoopCream(ctx))),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Enter your account email and we’ll send a link to choose a new '
              'password. The link opens in your browser and works for '
              '45 minutes.',
              style: TextStyle(color: stoopCream2(ctx), fontSize: 13.5),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.emailAddress,
              style: TextStyle(color: stoopCream(ctx)),
              decoration: stoopInput(ctx, 'you@example.com'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final email = controller.text.trim();
              if (!email.contains('@')) return;
              try {
                await BackporchApi().forgotPassword(email);
              } catch (_) {
                // Deliberately quiet — the answer is the same either way.
              }
              if (ctx.mounted) Navigator.pop(ctx, true);
            },
            child: const Text('Email me a link'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (sent == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'If that address has a Stoop account, a reset link is on its way. '
            'Check your email (and spam).',
          ),
        ),
      );
    }
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dob ?? DateTime(now.year - 18, now.month, now.day),
      firstDate: DateTime(1900),
      lastDate: now,
      helpText: 'Your date of birth (18+)',
    );
    if (picked != null) setState(() => _dob = picked);
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Container(
            padding: const EdgeInsets.all(30),
            decoration: BoxDecoration(
              gradient: stoopCardGradient(context),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: stoopBorder(context)),
              boxShadow: [
                const BoxShadow(
                  color: Color(0x59000000),
                  blurRadius: 30,
                  offset: Offset(0, 10),
                ),
                BoxShadow(
                  color: AppColors.stoopAmber.withValues(alpha: 0.04),
                  blurRadius: 60,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '🏡',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 26),
                ),
                const SizedBox(height: 6),
                Text(
                  'The Stoop',
                  textAlign: TextAlign.center,
                  style: stoopDisplay(context, size: 24),
                ),
                const SizedBox(height: 4),
                Text(
                  'Pull up a chair — sign in to browse and share.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: stoopMute(context)),
                ),
                const SizedBox(height: 20),
                _modeToggle(),
                const SizedBox(height: 20),
                _field('Email', _email, hint: 'you@example.com'),
                if (_isSignup) ...[
                  const SizedBox(height: 12),
                  _field(
                    'Display name',
                    _displayName,
                    hint: 'How others see you',
                  ),
                ],
                const SizedBox(height: 12),
                _field(
                  'Password',
                  _password,
                  hint: _isSignup ? 'At least 8 characters' : 'Your password',
                  obscure: true,
                ),
                if (_twoFactorRequired && !_isSignup) ...[
                  const SizedBox(height: 12),
                  _field('Authenticator code', _totp, hint: '123456'),
                ],
                if (_isSignup) ...[const SizedBox(height: 12), _dobField()],
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Text(
                    _error!,
                    style: TextStyle(
                      color: stoopEmberText(context),
                      fontSize: 13,
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                StoopAmberButton(
                  label: _isSignup ? 'Create account' : 'Sign in',
                  busy: _busy,
                  onPressed: _busy ? null : _submit,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                if (!_isSignup) ...[
                  const SizedBox(height: 12),
                  Center(
                    child: InkWell(
                      onTap: _busy ? null : _forgotPassword,
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        child: Text(
                          'Forgot password?',
                          style: TextStyle(
                            color: stoopTealText(context),
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Text(
                  '18+ only · one account works everywhere in Front Porch',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: stoopFaint(context), fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _modeToggle() {
    return Container(
      decoration: BoxDecoration(
        color: stoopBg1(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: stoopBorder(context)),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          _toggleButton('Sign in', !_isSignup, () {
            if (_isSignup) {
              setState(() {
                _isSignup = false;
                _error = null;
              });
            }
          }),
          _toggleButton('Create account', _isSignup, () {
            if (!_isSignup) {
              setState(() {
                _isSignup = true;
                _error = null;
                _twoFactorRequired = false; // not used during signup
              });
            }
          }),
        ],
      ),
    );
  }

  Widget _toggleButton(String label, bool selected, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: _busy ? null : onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? stoopAmberSoft(context) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: selected ? stoopAmberText(context) : stoopMute(context),
              fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    String? hint,
    bool obscure = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: stoopCream2(context),
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          obscureText: obscure,
          enabled: !_busy,
          style: TextStyle(color: stoopCream(context)),
          decoration: stoopInput(context, hint ?? ''),
        ),
      ],
    );
  }

  Widget _dobField() {
    final label = _dob == null
        ? 'Select your date of birth'
        : '${_dob!.year}-${_dob!.month.toString().padLeft(2, '0')}-${_dob!.day.toString().padLeft(2, '0')}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Date of birth',
          style: TextStyle(
            color: stoopCream2(context),
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        InkWell(
          onTap: _busy ? null : _pickDob,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            decoration: BoxDecoration(
              color: stoopBg1(context),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: stoopBorderHi(context)),
            ),
            child: Row(
              children: [
                Icon(Icons.cake_outlined, size: 18, color: stoopMute(context)),
                const SizedBox(width: 10),
                Text(
                  label,
                  style: TextStyle(
                    color: _dob == null
                        ? stoopFaint(context)
                        : stoopCream(context),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
