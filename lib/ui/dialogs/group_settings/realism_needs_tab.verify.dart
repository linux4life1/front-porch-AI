// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

part of 'realism_needs_tab.dart';

extension _GroupRealismNeedsVerify on _GroupRealismNeedsTabState {
  void _updateMemberVerificationEnabled(CharacterCard char, bool value) {
    final id = _getCharId(char);
    rebuildState(() {
      _verificationEnabled[id] = value;
      char.frontPorchExtensions =
          (char.frontPorchExtensions ?? FrontPorchExtensions()).copyWith(
            realismVerificationEnabled: value,
          );
      char.frontPorchExtensions?.ensureStableId();
    });

    persistGroupMemberPref(
      widget.chatService,
      id,
      'verificationEnabled',
      value,
    );
    _extPersister.schedule(char);
  }

  void _updateMemberVerificationMaxReprocesses(CharacterCard char, int value) {
    final id = _getCharId(char);
    rebuildState(() {
      _verificationMaxReprocesses[id] = value;
      char.frontPorchExtensions =
          (char.frontPorchExtensions ?? FrontPorchExtensions()).copyWith(
            realismVerificationMaxReprocesses: value,
          );
      char.frontPorchExtensions?.ensureStableId();
    });

    persistGroupMemberPref(
      widget.chatService,
      id,
      'verificationMaxReprocesses',
      value,
    );
    _extPersister.schedule(char);
  }

  void _updateMemberVerificationStrictness(CharacterCard char, int value) {
    final id = _getCharId(char);
    rebuildState(() {
      _verificationStrictness[id] = value;
      char.frontPorchExtensions =
          (char.frontPorchExtensions ?? FrontPorchExtensions()).copyWith(
            realismVerificationStrictness: value,
          );
      char.frontPorchExtensions?.ensureStableId();
    });

    persistGroupMemberPref(
      widget.chatService,
      id,
      'verificationStrictness',
      value,
    );
    _extPersister.schedule(char);
  }

  void _updateMemberNeedsDirectorAuthority(CharacterCard char, bool value) {
    final id = _getCharId(char);
    rebuildState(() {
      _needsDirectorAuthority[id] = value;
      char.frontPorchExtensions =
          (char.frontPorchExtensions ?? FrontPorchExtensions()).copyWith(
            realismNeedsDirectorAuthority: value,
          );
      char.frontPorchExtensions?.ensureStableId();
    });

    persistGroupMemberPref(
      widget.chatService,
      id,
      'needsDirectorAuthority',
      value,
    );
    _extPersister.schedule(char);
  }
}
