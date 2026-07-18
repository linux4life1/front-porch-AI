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
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: AppColors.cardOf(context),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.borderOf(context)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'The Stoop',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary(context),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Sign in to browse and share characters',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary(context)),
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
                _field('Password', _password, hint: '••••••••', obscure: true),
                if (_twoFactorRequired && !_isSignup) ...[
                  const SizedBox(height: 12),
                  _field(
                    'Authenticator code',
                    _totp,
                    hint: '123456',
                  ),
                ],
                if (_isSignup) ...[const SizedBox(height: 12), _dobField()],
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Text(
                    _error!,
                    style: TextStyle(
                      color: AppColors.resolve(
                        context,
                        Colors.redAccent,
                        Colors.red.shade700,
                      ),
                      fontSize: 13,
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(_isSignup ? 'Create account' : 'Sign in'),
                ),
                const SizedBox(height: 16),
                Text(
                  '18+ only · one account works everywhere in Front Porch',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.textTertiary(context),
                    fontSize: 12,
                  ),
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
        color: AppColors.surfaceContainerOf(context),
        borderRadius: BorderRadius.circular(10),
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
            color: selected ? AppColors.cardOf(context) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: selected
                  ? AppColors.textPrimary(context)
                  : AppColors.textSecondary(context),
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
            color: AppColors.textSecondary(context),
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          obscureText: obscure,
          enabled: !_busy,
          style: TextStyle(color: AppColors.textPrimary(context)),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: AppColors.textTertiary(context)),
            filled: true,
            fillColor: AppColors.surfaceContainerOf(context),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: AppColors.borderOf(context)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: AppColors.borderOf(context)),
            ),
          ),
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
            color: AppColors.textSecondary(context),
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 6),
        InkWell(
          onTap: _busy ? null : _pickDob,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerOf(context),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.borderOf(context)),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.cake_outlined,
                  size: 18,
                  color: AppColors.iconSecondary(context),
                ),
                const SizedBox(width: 10),
                Text(
                  label,
                  style: TextStyle(
                    color: _dob == null
                        ? AppColors.textTertiary(context)
                        : AppColors.textPrimary(context),
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
