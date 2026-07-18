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

import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:grpc/grpc.dart';

import 'dt_config_fb.dart';
import 'dt_proto.dart';
import 'dt_tensor.dart';

/// Draw Things' self-signed cert chain (public root material shipped by
/// Draw Things itself, embedded so the pure-Dart path needs no asset
/// plumbing). The server cert is issued to `localhost`, so like the old
/// Python client (grpc.ssl_target_name_override) we pin the TLS authority
/// to `localhost` regardless of the host actually dialed. Exposed via
/// [DrawThingsNativeClient.caChainPemForTest] so the golden suite can
/// guard the constant against accidental corruption.
const String _dtCaChainPem = '''
-----BEGIN CERTIFICATE-----
MIIFJzCCAw+gAwIBAgIUKkid2GhFrc7rFSbYgYimGr9/39swDQYJKoZIhvcNAQEL
BQAwHjEcMBoGA1UEAwwTRHJhdyBUaGluZ3MgUm9vdCBDQTAeFw0yNDEwMTUxNzI5
MDVaFw0zNDEwMTMxNzI5MDVaMBQxEjAQBgNVBAMMCWxvY2FsaG9zdDCCAiIwDQYJ
KoZIhvcNAQEBBQADggIPADCCAgoCggIBANNTYWDaCcYgeNdiFOjokU9yhegKZ344
2p27QjfAH66IBtn9jcLDhWDjAR68XSIpCRT0a9sQ+7buVc9oR7PbMy7yAellPAgt
EQ0Voyn7HU2tHnTzxtNypCojjjp8+l0uAv/NbkMadkuuFYfcPeQc6ql/S0aEtwMg
QoIWTGo2adgUS0CLk0sDkfL1JrL5kMb6AyskyyvNL5ztNvDkG6gHuZ2p3No3Zffd
JEd7thI7HD4754n3ctGSsiWdfobRbthl5DTHyEKsIzXNjeezXe0qN4nY87m9EDuq
3LXHaka0BUZBIqIjzvhZmd1A+5JiFC1bqq0aXJTKSJtwxU4xXeJd+5dB7HTf29gU
bPhqlvqKqNc8tiUBThyWe4DdH+ZCcAAismVJnTCB1y6JanI4XNgPsWoHeeh8wqo1
ZQitLeSxJNu9bS2+E6OocofzAN7DtT6jksr61Rx6tv8tuExb0mdiiRMXPIvQrG63
dju65QcUXA4YHFKqbOwsXB1SVvJhOFhkKVQtFdZF+DR29HwAbFlbC3ombWdnFzqp
oIwLthvAqxyJWkQP8Dz4aYQQ7OW2fpFvAxPY6mfr897hjbPQaHpo2UrWRMkXUSUD
BD5JrSqEZQjU8fBYQTYgtLWyFMUWuCgq3WVNCVkyjRh6pjS7EyVdaU6WFnhS8FiH
1uUeyP2dIVtFAgMBAAGjZzBlMCMGA1UdEQQcMBqCCWxvY2FsaG9zdIIBKocEfwAA
AYcEAAAAADAdBgNVHQ4EFgQUpp90cWHYlSyBVaQ/lFaPpzjVRWwwHwYDVR0jBBgw
FoAUhmFk2qHWAU6/3u6FyCnk2vaV0fswDQYJKoZIhvcNAQELBQADggIBAAm/Mfsj
+w67gT/Ke6bk0v6nd7UuGNCqeXtoFZAXZYP/IsbxsGY9wLJpOIYemAbHqmidhqUO
8I9dB5Ny3c6m2yivF1lkI5VgyDeDWtKpqYuhCiSGByx3bNDTO8NAYXlJtr++fUQS
Focs7gbh1ugc6vWTS2oIH3GETawBvvo8VmiCMs0k6fWXAz5b7PkAwk8l471DiNm9
tej8aiIapsUuwFTsaz74FTDOAIAy4yUXBqAL2w0cWlBE9kcAk4GaWivOm0WJEvES
zM2YnqjixG5BBmmeWHNG9PXXIArlcrgydimC8Wc6slpYhzzH4X9CySaxgEpaQwmq
Xoto8mo+vVB071CQxNz/SWsP0a2M+PH5yewg4TrKqwkMj27ka79uvxg3z1ykeSyM
PNDXN7+NJCTxMVpdgTx/SY4H04jHYqpPrfmaHAHx6Telv7HpLVDyNPMmnK9nPUZ8
tjQLViz4dGgr57WbsUPZ3NIpwmHxlDf9+1mw81LIx+IGUhnzwTdRXykiCqu86V8+
eFYZ4F3SBnZujfwiWIDnELEH3G1IIIrp1lVycWbHLjepnKGLq2klus05Bm+hM3QX
ntVlSXrA96h+1FtOV4zbGo2kN+CUuR02HbMkVGGrgVLLSPsnH89We1bbcJz7icsn
f2enYU9onGERV75o7YsCl7n4qFHdPgdp/Dum
-----END CERTIFICATE-----
''';

/// Pure-Dart Draw Things gRPC client — replaces the PyInstaller sidecar for
/// test/models/generate. Wire behavior mirrors tools/dt-grpc-python/client.py
/// 1:1 (TLS with the bundled CA + `localhost` authority, Echo("models") model
/// listing, FlatBuffer config, NNC tensor CAS for img2img, server-streamed
/// signpost progress). Throws on any failure; DrawThingsGrpcService catches
/// and falls back to the sidecar path.
class DrawThingsNativeClient {
  final String host;
  final int port;
  ClientChannel? _channel;

  DrawThingsNativeClient({required this.host, required this.port});

  static final _echoMethod = ClientMethod<Uint8List, EchoReply>(
    '/ImageGenerationService/Echo',
    (r) => r,
    EchoReply.decode,
  );
  static final _generateMethod =
      ClientMethod<ImageGenerationRequest, ImageGenerationResponse>(
        '/ImageGenerationService/GenerateImage',
        (r) => r.encode().toList(),
        ImageGenerationResponse.decode,
      );

  /// The embedded cert chain, exposed for the golden suite's sanity check
  /// (its former source file left with the deleted Python sidecar).
  @visibleForTesting
  static String get caChainPemForTest => _dtCaChainPem;

  /// SHA-256 of the pinned cert's DER, for exact-match pinning below.
  static final String _pinnedDerSha256 = sha256
      .convert(
        base64.decode(
          _dtCaChainPem
              .replaceAll(RegExp(r'-----[A-Z ]+-----'), '')
              .replaceAll(RegExp(r'\s'), ''),
        ),
      )
      .toString();

  ClientChannel _connect() {
    return _channel ??= ClientChannel(
      host,
      port: port,
      options: ChannelOptions(
        credentials: ChannelCredentials.secure(
          certificates: utf8.encode(_dtCaChainPem),
          authority: 'localhost',
          // The pinned PEM is Draw Things' LEAF cert (issued BY "Draw Things
          // Root CA", whose root is not distributed). Python gRPC accepts a
          // leaf as a trust anchor (partial-chain verification); dart:io does
          // NOT — it walks to the absent root and fails the handshake, so
          // chain verification alone can never succeed against a real DT
          // server. Exact-match pinning of the presented cert is the correct
          // (and stricter) equivalent: accept exactly the cert we ship.
          onBadCertificate: (cert, host) =>
              sha256.convert(cert.der).toString() == _pinnedDerSha256,
        ),
        // Draw Things gzip-compresses responses. Python gRPC negotiates that
        // automatically; grpc-dart only accepts compressed messages when a
        // codec registry says so — without this, every reply died as
        // DATA_LOSS 'Error parsing response' (field report from the first
        // signed nightly, reproduced + verified fixed with tool-probe
        // against a live server).
        codecRegistry: CodecRegistry(
          codecs: const [GzipCodec(), IdentityCodec()],
        ),
      ),
    );
  }

  Future<void> shutdown() async {
    final ch = _channel;
    _channel = null;
    await ch?.shutdown();
  }

  Future<String> echo({Duration timeout = const Duration(seconds: 10)}) async {
    final reply = await _rawEcho('hello', timeout);
    return reply.message;
  }

  /// The raw Echo("models") file list — the caller applies the same
  /// checkpoint/LoRA filtering the sidecar did.
  Future<List<String>> listFiles({
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final reply = await _rawEcho('models', timeout);
    return reply.files;
  }

  Future<EchoReply> _rawEcho(String name, Duration timeout) {
    final ch = _connect();
    final call = ch.createCall(
      _echoMethod,
      Stream.value(encodeEchoRequest(name)),
      CallOptions(timeout: timeout),
    );
    return call.response.single.whenComplete(() => call.cancel());
  }

  /// Run one generation. [cfg] is the same config map the service builds for
  /// the sidecar. Returns decoded PNG bytes of the first generated image.
  Future<Uint8List> generate({
    required String prompt,
    required String negativePrompt,
    required Map<String, dynamic> cfg,
    Uint8List? referenceImageBytes,
    void Function(int step)? onStep,
    Duration timeout = const Duration(seconds: 600),
  }) async {
    final configBytes = buildGenerationConfig(cfg);

    Uint8List? imageHash;
    final contents = <Uint8List>[];
    if (referenceImageBytes != null && referenceImageBytes.isNotEmpty) {
      // Content-addressable storage: tensor payload in `contents`, its
      // sha256 in `image` — resolution is latent size * 64 (Python parity).
      final tensor = imageToNncTensor(
        referenceImageBytes,
        targetWidth: ((cfg['start_width'] as num?)?.toInt() ?? 16) * 64,
        targetHeight: ((cfg['start_height'] as num?)?.toInt() ?? 16) * 64,
      );
      imageHash = Uint8List.fromList(sha256.convert(tensor).bytes);
      contents.add(tensor);
    }

    final request = ImageGenerationRequest(
      image: imageHash,
      scaleFactor: 1,
      prompt: prompt,
      negativePrompt: negativePrompt,
      configuration: configBytes,
      contents: contents,
    );

    final ch = _connect();
    final call = ch.createCall(
      _generateMethod,
      Stream.value(request),
      CallOptions(timeout: timeout),
    );
    final images = <Uint8List>[];
    try {
      await for (final resp in call.response) {
        if (resp.signpost == DtSignpost.sampling && resp.samplingStep != null) {
          onStep?.call(resp.samplingStep!);
        }
        images.addAll(resp.generatedImages.where((d) => d.isNotEmpty));
      }
    } finally {
      unawaited(call.cancel().catchError((_) {}));
    }

    if (images.isEmpty) {
      throw Exception('Generation produced no images');
    }
    debugPrint(
      '[DT-Native] stream complete: ${images.length} payload(s), '
      'first ${images.first.length} bytes',
    );
    return decodeGeneratedImage(images.first);
  }
}
