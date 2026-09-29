// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/services/image/civitai_client.dart';
import 'package:front_porch_ai/services/image/civitai_credentials.dart';
import 'package:front_porch_ai/services/image/civitai_errors.dart';
import 'package:front_porch_ai/services/image/civitai_fetch.dart';
import 'package:front_porch_ai/services/image/civitai_version.dart';
import 'package:front_porch_ai/services/image/studio_model_roots.dart';

/// Saves one planned file and returns where it landed.
typedef CivitaiSaveCall =
    Future<String> Function(
      CivitaiDownloadPlan plan, {
      void Function(int received, int? total)? onProgress,
      CivitaiCancel? cancel,
    });

Future<String> saveCivitaiToDisk(
  CivitaiDownloadPlan plan, {
  void Function(int received, int? total)? onProgress,
  CivitaiCancel? cancel,
}) {
  return downloadCivitaiPlan(plan, onProgress: onProgress, cancel: cancel);
}

/// How one Download press ended.
sealed class CivitaiInstallResult {
  const CivitaiInstallResult();
}

/// The file is in the models folder: just downloaded, or already there with
/// the size CivitAI lists.
class CivitaiInstalled extends CivitaiInstallResult {
  const CivitaiInstalled(this.name);

  final String name;
}

/// The person stopped it.
class CivitaiInstallStopped extends CivitaiInstallResult {
  const CivitaiInstallStopped();
}

class CivitaiInstallFailed extends CivitaiInstallResult {
  const CivitaiInstallFailed(this.message, {this.needFolder = false});

  final String message;

  /// The fix is to pick the models folder.
  final bool needFolder;
}

const String _kRemoteComfy =
    'This ComfyUI is on another computer. Save the download on that computer.';

/// Downloads [row]. What is saved comes from CivitAI's own listing of the
/// version: its file, its folder, its size and checksum. The search row only
/// says which version to ask about.
Future<CivitaiInstallResult> installCivitaiRow({
  required CivitaiModelRow row,
  required String backend,
  required bool lora,
  required bool adult,
  required bool adultAllowed,
  required CivitaiVersionFetch versionFetch,
  required CivitaiSaveCall saveCall,
  required CivitaiCancel cancel,
  required void Function(int received, int? total) onProgress,
}) async {
  final versionId = row.versionId;
  if (versionId == null) {
    return const CivitaiInstallFailed('That row has no file to download.');
  }
  String? wanted = row.filename;
  try {
    if (backend == 'comfyui' && await comfyStudioIsRemote()) {
      return const CivitaiInstallFailed(_kRemoteComfy);
    }
    final root = await savedStudioModelRoot(backend);
    final gone = root == null && await studioSavedRootMissing(backend);
    final blocked = civitaiBlockedDownload(
      backend: backend,
      savedRoot: root,
      savedGone: gone,
    );
    if (blocked != null || root == null) {
      return CivitaiInstallFailed(
        blocked ?? 'Pick your models folder on this computer first',
        needFolder:
            root == null && (backend == 'comfyui' || backend == 'a1111'),
      );
    }
    if (cancel.isCancelled) return const CivitaiInstallStopped();
    final relay = CivitaiRelay(await CivitaiCredentialStore.open());
    final key = await relay.store.read('local');
    if (key == null) {
      return _failed(const CivitaiDownloadException(CivitaiFailure.keyMissing));
    }
    final lookup = await versionFetch(
      versionId: versionId,
      adult: adult,
      authorization: civitaiBearer(key),
    );
    if (cancel.isCancelled) return const CivitaiInstallStopped();
    final version = lookup.version;
    if (lookup.kind != CivitaiLookupKind.ok || version == null) {
      return _failed(CivitaiDownloadException(_lookupFailure(lookup.kind)));
    }
    wanted ??= civitaiPickVersionFile(version)?.name ?? '';
    final plan = await relay.planDownload(
      accountId: 'local',
      version: version,
      filename: wanted,
      adult: adult,
      adultAllowed: adultAllowed,
      savedRoot: root,
      fromLoraSheet: lora,
      backend: backend,
      typeFolders: await studioModelTypeFolders(backend, root),
    );
    final landed = await saveCall(plan, cancel: cancel, onProgress: onProgress);
    return CivitaiInstalled(p.basename(landed));
  } on CivitaiDownloadException catch (e) {
    if (e.kind == CivitaiFailure.cancelled) {
      return const CivitaiInstallStopped();
    }
    if (e.kind == CivitaiFailure.exists && wanted != null) {
      return CivitaiInstalled(wanted);
    }
    return _failed(e);
  } on CivitaiKeyStoreException catch (e) {
    return CivitaiInstallFailed(e.message);
  } catch (e) {
    debugPrint('civitai download failed: ${e.runtimeType}');
    if (cancel.isCancelled) return const CivitaiInstallStopped();
    return const CivitaiInstallFailed('CivitAI download failed.');
  }
}

CivitaiInstallFailed _failed(CivitaiDownloadException e) {
  return CivitaiInstallFailed(e.message);
}

CivitaiFailure _lookupFailure(CivitaiLookupKind kind) {
  return switch (kind) {
    CivitaiLookupKind.needsCredential => CivitaiFailure.keyRefused,
    CivitaiLookupKind.locked => CivitaiFailure.locked,
    CivitaiLookupKind.notFound => CivitaiFailure.notFound,
    _ => CivitaiFailure.network,
  };
}
