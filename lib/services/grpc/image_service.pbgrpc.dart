// This is a generated file - do not edit.
//
// Generated from image_service.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:async' as $async;
import 'dart:core' as $core;

import 'package:grpc/service_api.dart' as $grpc;
import 'package:protobuf/protobuf.dart' as $pb;

import 'image_service.pb.dart' as $0;

export 'image_service.pb.dart';

@$pb.GrpcServiceName('ImageGenerationService')
class ImageGenerationServiceClient extends $grpc.Client {
  /// The hostname for this service.
  static const $core.String defaultHost = '';

  /// OAuth scopes needed for the client.
  static const $core.List<$core.String> oauthScopes = [
    '',
  ];

  ImageGenerationServiceClient(super.channel,
      {super.options, super.interceptors});

  $grpc.ResponseStream<$0.ImageGenerationResponse> generateImage(
    $0.ImageGenerationRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createStreamingCall(
        _$generateImage, $async.Stream.fromIterable([request]),
        options: options);
  }

  $grpc.ResponseFuture<$0.FileExistenceResponse> filesExist(
    $0.FileListRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$filesExist, request, options: options);
  }

  $grpc.ResponseStream<$0.UploadResponse> uploadFile(
    $async.Stream<$0.FileUploadRequest> request, {
    $grpc.CallOptions? options,
  }) {
    return $createStreamingCall(_$uploadFile, request, options: options);
  }

  $grpc.ResponseFuture<$0.EchoReply> echo(
    $0.EchoRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$echo, request, options: options);
  }

  $grpc.ResponseFuture<$0.PubkeyResponse> pubkey(
    $0.PubkeyRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$pubkey, request, options: options);
  }

  $grpc.ResponseFuture<$0.HoursResponse> hours(
    $0.HoursRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$hours, request, options: options);
  }

  // method descriptors

  static final _$generateImage =
      $grpc.ClientMethod<$0.ImageGenerationRequest, $0.ImageGenerationResponse>(
          '/ImageGenerationService/GenerateImage',
          ($0.ImageGenerationRequest value) => value.writeToBuffer(),
          $0.ImageGenerationResponse.fromBuffer);
  static final _$filesExist =
      $grpc.ClientMethod<$0.FileListRequest, $0.FileExistenceResponse>(
          '/ImageGenerationService/FilesExist',
          ($0.FileListRequest value) => value.writeToBuffer(),
          $0.FileExistenceResponse.fromBuffer);
  static final _$uploadFile =
      $grpc.ClientMethod<$0.FileUploadRequest, $0.UploadResponse>(
          '/ImageGenerationService/UploadFile',
          ($0.FileUploadRequest value) => value.writeToBuffer(),
          $0.UploadResponse.fromBuffer);
  static final _$echo = $grpc.ClientMethod<$0.EchoRequest, $0.EchoReply>(
      '/ImageGenerationService/Echo',
      ($0.EchoRequest value) => value.writeToBuffer(),
      $0.EchoReply.fromBuffer);
  static final _$pubkey =
      $grpc.ClientMethod<$0.PubkeyRequest, $0.PubkeyResponse>(
          '/ImageGenerationService/Pubkey',
          ($0.PubkeyRequest value) => value.writeToBuffer(),
          $0.PubkeyResponse.fromBuffer);
  static final _$hours = $grpc.ClientMethod<$0.HoursRequest, $0.HoursResponse>(
      '/ImageGenerationService/Hours',
      ($0.HoursRequest value) => value.writeToBuffer(),
      $0.HoursResponse.fromBuffer);
}

@$pb.GrpcServiceName('ImageGenerationService')
abstract class ImageGenerationServiceBase extends $grpc.Service {
  $core.String get $name => 'ImageGenerationService';

  ImageGenerationServiceBase() {
    $addMethod($grpc.ServiceMethod<$0.ImageGenerationRequest,
            $0.ImageGenerationResponse>(
        'GenerateImage',
        generateImage_Pre,
        false,
        true,
        ($core.List<$core.int> value) =>
            $0.ImageGenerationRequest.fromBuffer(value),
        ($0.ImageGenerationResponse value) => value.writeToBuffer()));
    $addMethod(
        $grpc.ServiceMethod<$0.FileListRequest, $0.FileExistenceResponse>(
            'FilesExist',
            filesExist_Pre,
            false,
            false,
            ($core.List<$core.int> value) =>
                $0.FileListRequest.fromBuffer(value),
            ($0.FileExistenceResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.FileUploadRequest, $0.UploadResponse>(
        'UploadFile',
        uploadFile,
        true,
        true,
        ($core.List<$core.int> value) => $0.FileUploadRequest.fromBuffer(value),
        ($0.UploadResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.EchoRequest, $0.EchoReply>(
        'Echo',
        echo_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.EchoRequest.fromBuffer(value),
        ($0.EchoReply value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.PubkeyRequest, $0.PubkeyResponse>(
        'Pubkey',
        pubkey_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.PubkeyRequest.fromBuffer(value),
        ($0.PubkeyResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.HoursRequest, $0.HoursResponse>(
        'Hours',
        hours_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.HoursRequest.fromBuffer(value),
        ($0.HoursResponse value) => value.writeToBuffer()));
  }

  $async.Stream<$0.ImageGenerationResponse> generateImage_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.ImageGenerationRequest> $request) async* {
    yield* generateImage($call, await $request);
  }

  $async.Stream<$0.ImageGenerationResponse> generateImage(
      $grpc.ServiceCall call, $0.ImageGenerationRequest request);

  $async.Future<$0.FileExistenceResponse> filesExist_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.FileListRequest> $request) async {
    return filesExist($call, await $request);
  }

  $async.Future<$0.FileExistenceResponse> filesExist(
      $grpc.ServiceCall call, $0.FileListRequest request);

  $async.Stream<$0.UploadResponse> uploadFile(
      $grpc.ServiceCall call, $async.Stream<$0.FileUploadRequest> request);

  $async.Future<$0.EchoReply> echo_Pre(
      $grpc.ServiceCall $call, $async.Future<$0.EchoRequest> $request) async {
    return echo($call, await $request);
  }

  $async.Future<$0.EchoReply> echo(
      $grpc.ServiceCall call, $0.EchoRequest request);

  $async.Future<$0.PubkeyResponse> pubkey_Pre(
      $grpc.ServiceCall $call, $async.Future<$0.PubkeyRequest> $request) async {
    return pubkey($call, await $request);
  }

  $async.Future<$0.PubkeyResponse> pubkey(
      $grpc.ServiceCall call, $0.PubkeyRequest request);

  $async.Future<$0.HoursResponse> hours_Pre(
      $grpc.ServiceCall $call, $async.Future<$0.HoursRequest> $request) async {
    return hours($call, await $request);
  }

  $async.Future<$0.HoursResponse> hours(
      $grpc.ServiceCall call, $0.HoursRequest request);
}
