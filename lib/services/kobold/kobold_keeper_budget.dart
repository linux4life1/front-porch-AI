// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Whether the slot keeper may look after chats for the engine that is
// loaded, and how many. Decided from what the engine was given, not asked of
// it: a rule that fails here saves a call to an engine that cannot help.

import 'package:front_porch_ai/utils/utils.dart';

import 'kcpps_codec.dart';

/// What the keeper does for one loaded model: keeps [chats] conversations,
/// or stays out and says [why].
class KoboldKeeperPlan {
  const KoboldKeeperPlan.keep(this.chats) : why = null, undecided = false;
  const KoboldKeeperPlan.off(String this.why) : chats = 0, undecided = false;

  /// What the engine runs is not known yet; ask again at the next request.
  const KoboldKeeperPlan.later() : chats = 0, why = null, undecided = true;

  final int chats;

  /// Plain words, for the engine log.
  final String? why;
  final bool undecided;

  bool get keeps => chats > 0;
}

/// Said at the start when auto mode leaves the chats to KoboldCpp's own
/// smart cache because keeping them from the app failed for this model with
/// this KoboldCpp before.
const String kKeeperFailedNote =
    "KoboldCpp's own smart cache looks after chats for this model: keeping "
    'them ready from Front Porch AI did not work with this version of '
    'KoboldCpp before.';

/// The memory the saved chats may use, in MB: the biggest one can be (a chat
/// that fills the context), what the system has free, and what the model
/// itself takes of it.
typedef KoboldKeeperMemory = ({int slotMb, int freeRamMb, int modelRamMb});

/// The keeper's plan for the config the engine was given.
///
/// It stays out when saved chats cannot help: the engine is not the app's
/// own, KoboldCpp's smart cache is on (the user's own choice, and the two
/// are not meant to run together), fast forward is off, sliding window is
/// left to KoboldCpp for a model that has it, the model has recurrent layers
/// (a saved state only matches a prompt that starts with all of it, which
/// the next chat prompt never does), or the engine answers several requests
/// at once.
KoboldKeeperPlan koboldKeeperPlan({
  required bool ownEngine,
  required Map<String, dynamic>? config,
  required GGUFModelInfo? info,
  KoboldKeeperMemory? memory,
}) {
  if (!ownEngine) {
    return const KoboldKeeperPlan.off(
      'This KoboldCpp was not started by Front Porch AI, so its saved chats '
      'are left alone.',
    );
  }
  if (config == null) return const KoboldKeeperPlan.later();
  if (_number(config['smartcache']) > 0) {
    return const KoboldKeeperPlan.off(
      "This preset uses KoboldCpp's own smart cache, so chats are left to it.",
    );
  }
  if (config['nofastforward'] == true) {
    return const KoboldKeeperPlan.off(
      'Fast forward is off here, so a saved chat could not be picked up '
      'again.',
    );
  }
  if (info == null) {
    return const KoboldKeeperPlan.off(
      'The model could not be read, so no chats are kept ready for it.',
    );
  }
  if (info.recurrentStateBytes > 0) {
    return const KoboldKeeperPlan.off(
      'This model cannot go back to an earlier point in a chat, so '
      "KoboldCpp's own smart cache looks after its chats.",
    );
  }
  if (kcppsLeavesSwaToKobold(config) && info.hasSlidingWindow) {
    return const KoboldKeeperPlan.off(
      'This model reads the whole chat again every turn with its sliding '
      'window left as KoboldCpp has it, so saved chats would not help.',
    );
  }
  if (_number(config['parallelrequests']) > 1) {
    return const KoboldKeeperPlan.off(
      'KoboldCpp is set to answer several requests at once, so no chats are '
      'kept ready.',
    );
  }
  if (memory == null) return const KoboldKeeperPlan.keep(1);
  final fit = suggestSmartCacheSlots(
    promptKinds: kKoboldSaveSlots,
    slotMb: memory.slotMb,
    freeRamMb: memory.freeRamMb,
    modelRamMb: memory.modelRamMb,
  );
  return fit.slots > 0
      ? KoboldKeeperPlan.keep(fit.slots)
      : const KoboldKeeperPlan.off(
          'There is not enough free memory to keep chats ready next to this '
          'model.',
        );
}

int _number(Object? v) =>
    v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;
