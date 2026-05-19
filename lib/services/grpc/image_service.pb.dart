// This is a generated file - do not edit.
//
// Generated from image_service.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

import 'image_service.pbenum.dart';

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

export 'image_service.pbenum.dart';

class EchoRequest extends $pb.GeneratedMessage {
  factory EchoRequest({
    $core.String? name,
    $core.String? sharedSecret,
  }) {
    final result = create();
    if (name != null) result.name = name;
    if (sharedSecret != null) result.sharedSecret = sharedSecret;
    return result;
  }

  EchoRequest._();

  factory EchoRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory EchoRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'EchoRequest',
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'name')
    ..aOS(2, _omitFieldNames ? '' : 'sharedSecret', protoName: 'sharedSecret')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  EchoRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  EchoRequest copyWith(void Function(EchoRequest) updates) =>
      super.copyWith((message) => updates(message as EchoRequest))
          as EchoRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EchoRequest create() => EchoRequest._();
  @$core.override
  EchoRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static EchoRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<EchoRequest>(create);
  static EchoRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get name => $_getSZ(0);
  @$pb.TagNumber(1)
  set name($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasName() => $_has(0);
  @$pb.TagNumber(1)
  void clearName() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get sharedSecret => $_getSZ(1);
  @$pb.TagNumber(2)
  set sharedSecret($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSharedSecret() => $_has(1);
  @$pb.TagNumber(2)
  void clearSharedSecret() => $_clearField(2);
}

class ComputeUnitThreshold extends $pb.GeneratedMessage {
  factory ComputeUnitThreshold({
    $core.double? community,
    $core.double? plus,
    $fixnum.Int64? expireAt,
  }) {
    final result = create();
    if (community != null) result.community = community;
    if (plus != null) result.plus = plus;
    if (expireAt != null) result.expireAt = expireAt;
    return result;
  }

  ComputeUnitThreshold._();

  factory ComputeUnitThreshold.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ComputeUnitThreshold.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ComputeUnitThreshold',
      createEmptyInstance: create)
    ..aD(1, _omitFieldNames ? '' : 'community')
    ..aD(2, _omitFieldNames ? '' : 'plus')
    ..aInt64(3, _omitFieldNames ? '' : 'expireAt', protoName: 'expireAt')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ComputeUnitThreshold clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ComputeUnitThreshold copyWith(void Function(ComputeUnitThreshold) updates) =>
      super.copyWith((message) => updates(message as ComputeUnitThreshold))
          as ComputeUnitThreshold;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ComputeUnitThreshold create() => ComputeUnitThreshold._();
  @$core.override
  ComputeUnitThreshold createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ComputeUnitThreshold getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ComputeUnitThreshold>(create);
  static ComputeUnitThreshold? _defaultInstance;

  @$pb.TagNumber(1)
  $core.double get community => $_getN(0);
  @$pb.TagNumber(1)
  set community($core.double value) => $_setDouble(0, value);
  @$pb.TagNumber(1)
  $core.bool hasCommunity() => $_has(0);
  @$pb.TagNumber(1)
  void clearCommunity() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.double get plus => $_getN(1);
  @$pb.TagNumber(2)
  set plus($core.double value) => $_setDouble(1, value);
  @$pb.TagNumber(2)
  $core.bool hasPlus() => $_has(1);
  @$pb.TagNumber(2)
  void clearPlus() => $_clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get expireAt => $_getI64(2);
  @$pb.TagNumber(3)
  set expireAt($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(3)
  $core.bool hasExpireAt() => $_has(2);
  @$pb.TagNumber(3)
  void clearExpireAt() => $_clearField(3);
}

class EchoReply extends $pb.GeneratedMessage {
  factory EchoReply({
    $core.String? message,
    $core.Iterable<$core.String>? files,
    MetadataOverride? override,
    $core.bool? sharedSecretMissing,
    ComputeUnitThreshold? thresholds,
    $fixnum.Int64? serverIdentifier,
  }) {
    final result = create();
    if (message != null) result.message = message;
    if (files != null) result.files.addAll(files);
    if (override != null) result.override = override;
    if (sharedSecretMissing != null)
      result.sharedSecretMissing = sharedSecretMissing;
    if (thresholds != null) result.thresholds = thresholds;
    if (serverIdentifier != null) result.serverIdentifier = serverIdentifier;
    return result;
  }

  EchoReply._();

  factory EchoReply.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory EchoReply.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'EchoReply',
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'message')
    ..pPS(2, _omitFieldNames ? '' : 'files')
    ..aOM<MetadataOverride>(3, _omitFieldNames ? '' : 'override',
        subBuilder: MetadataOverride.create)
    ..aOB(4, _omitFieldNames ? '' : 'sharedSecretMissing',
        protoName: 'sharedSecretMissing')
    ..aOM<ComputeUnitThreshold>(5, _omitFieldNames ? '' : 'thresholds',
        subBuilder: ComputeUnitThreshold.create)
    ..a<$fixnum.Int64>(
        6, _omitFieldNames ? '' : 'serverIdentifier', $pb.PbFieldType.OU6,
        protoName: 'serverIdentifier', defaultOrMaker: $fixnum.Int64.ZERO)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  EchoReply clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  EchoReply copyWith(void Function(EchoReply) updates) =>
      super.copyWith((message) => updates(message as EchoReply)) as EchoReply;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EchoReply create() => EchoReply._();
  @$core.override
  EchoReply createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static EchoReply getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EchoReply>(create);
  static EchoReply? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get message => $_getSZ(0);
  @$pb.TagNumber(1)
  set message($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasMessage() => $_has(0);
  @$pb.TagNumber(1)
  void clearMessage() => $_clearField(1);

  @$pb.TagNumber(2)
  $pb.PbList<$core.String> get files => $_getList(1);

  @$pb.TagNumber(3)
  MetadataOverride get override => $_getN(2);
  @$pb.TagNumber(3)
  set override(MetadataOverride value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasOverride() => $_has(2);
  @$pb.TagNumber(3)
  void clearOverride() => $_clearField(3);
  @$pb.TagNumber(3)
  MetadataOverride ensureOverride() => $_ensure(2);

  @$pb.TagNumber(4)
  $core.bool get sharedSecretMissing => $_getBF(3);
  @$pb.TagNumber(4)
  set sharedSecretMissing($core.bool value) => $_setBool(3, value);
  @$pb.TagNumber(4)
  $core.bool hasSharedSecretMissing() => $_has(3);
  @$pb.TagNumber(4)
  void clearSharedSecretMissing() => $_clearField(4);

  @$pb.TagNumber(5)
  ComputeUnitThreshold get thresholds => $_getN(4);
  @$pb.TagNumber(5)
  set thresholds(ComputeUnitThreshold value) => $_setField(5, value);
  @$pb.TagNumber(5)
  $core.bool hasThresholds() => $_has(4);
  @$pb.TagNumber(5)
  void clearThresholds() => $_clearField(5);
  @$pb.TagNumber(5)
  ComputeUnitThreshold ensureThresholds() => $_ensure(4);

  @$pb.TagNumber(6)
  $fixnum.Int64 get serverIdentifier => $_getI64(5);
  @$pb.TagNumber(6)
  set serverIdentifier($fixnum.Int64 value) => $_setInt64(5, value);
  @$pb.TagNumber(6)
  $core.bool hasServerIdentifier() => $_has(5);
  @$pb.TagNumber(6)
  void clearServerIdentifier() => $_clearField(6);
}

class FileListRequest extends $pb.GeneratedMessage {
  factory FileListRequest({
    $core.Iterable<$core.String>? files,
    $core.Iterable<$core.String>? filesWithHash,
    $core.String? sharedSecret,
  }) {
    final result = create();
    if (files != null) result.files.addAll(files);
    if (filesWithHash != null) result.filesWithHash.addAll(filesWithHash);
    if (sharedSecret != null) result.sharedSecret = sharedSecret;
    return result;
  }

  FileListRequest._();

  factory FileListRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory FileListRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'FileListRequest',
      createEmptyInstance: create)
    ..pPS(1, _omitFieldNames ? '' : 'files')
    ..pPS(2, _omitFieldNames ? '' : 'filesWithHash', protoName: 'filesWithHash')
    ..aOS(3, _omitFieldNames ? '' : 'sharedSecret', protoName: 'sharedSecret')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FileListRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FileListRequest copyWith(void Function(FileListRequest) updates) =>
      super.copyWith((message) => updates(message as FileListRequest))
          as FileListRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static FileListRequest create() => FileListRequest._();
  @$core.override
  FileListRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static FileListRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<FileListRequest>(create);
  static FileListRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<$core.String> get files => $_getList(0);

  @$pb.TagNumber(2)
  $pb.PbList<$core.String> get filesWithHash => $_getList(1);

  @$pb.TagNumber(3)
  $core.String get sharedSecret => $_getSZ(2);
  @$pb.TagNumber(3)
  set sharedSecret($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasSharedSecret() => $_has(2);
  @$pb.TagNumber(3)
  void clearSharedSecret() => $_clearField(3);
}

class FileExistenceResponse extends $pb.GeneratedMessage {
  factory FileExistenceResponse({
    $core.Iterable<$core.String>? files,
    $core.Iterable<$core.bool>? existences,
    $core.Iterable<$core.List<$core.int>>? hashes,
  }) {
    final result = create();
    if (files != null) result.files.addAll(files);
    if (existences != null) result.existences.addAll(existences);
    if (hashes != null) result.hashes.addAll(hashes);
    return result;
  }

  FileExistenceResponse._();

  factory FileExistenceResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory FileExistenceResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'FileExistenceResponse',
      createEmptyInstance: create)
    ..pPS(1, _omitFieldNames ? '' : 'files')
    ..p<$core.bool>(2, _omitFieldNames ? '' : 'existences', $pb.PbFieldType.KB)
    ..p<$core.List<$core.int>>(
        3, _omitFieldNames ? '' : 'hashes', $pb.PbFieldType.PY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FileExistenceResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FileExistenceResponse copyWith(
          void Function(FileExistenceResponse) updates) =>
      super.copyWith((message) => updates(message as FileExistenceResponse))
          as FileExistenceResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static FileExistenceResponse create() => FileExistenceResponse._();
  @$core.override
  FileExistenceResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static FileExistenceResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<FileExistenceResponse>(create);
  static FileExistenceResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<$core.String> get files => $_getList(0);

  @$pb.TagNumber(2)
  $pb.PbList<$core.bool> get existences => $_getList(1);

  @$pb.TagNumber(3)
  $pb.PbList<$core.List<$core.int>> get hashes => $_getList(2);
}

class MetadataOverride extends $pb.GeneratedMessage {
  factory MetadataOverride({
    $core.List<$core.int>? models,
    $core.List<$core.int>? loras,
    $core.List<$core.int>? controlNets,
    $core.List<$core.int>? textualInversions,
    $core.List<$core.int>? upscalers,
  }) {
    final result = create();
    if (models != null) result.models = models;
    if (loras != null) result.loras = loras;
    if (controlNets != null) result.controlNets = controlNets;
    if (textualInversions != null) result.textualInversions = textualInversions;
    if (upscalers != null) result.upscalers = upscalers;
    return result;
  }

  MetadataOverride._();

  factory MetadataOverride.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory MetadataOverride.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'MetadataOverride',
      createEmptyInstance: create)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'models', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(
        2, _omitFieldNames ? '' : 'loras', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(
        3, _omitFieldNames ? '' : 'controlNets', $pb.PbFieldType.OY,
        protoName: 'controlNets')
    ..a<$core.List<$core.int>>(
        4, _omitFieldNames ? '' : 'textualInversions', $pb.PbFieldType.OY,
        protoName: 'textualInversions')
    ..a<$core.List<$core.int>>(
        5, _omitFieldNames ? '' : 'upscalers', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MetadataOverride clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MetadataOverride copyWith(void Function(MetadataOverride) updates) =>
      super.copyWith((message) => updates(message as MetadataOverride))
          as MetadataOverride;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static MetadataOverride create() => MetadataOverride._();
  @$core.override
  MetadataOverride createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static MetadataOverride getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<MetadataOverride>(create);
  static MetadataOverride? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get models => $_getN(0);
  @$pb.TagNumber(1)
  set models($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasModels() => $_has(0);
  @$pb.TagNumber(1)
  void clearModels() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get loras => $_getN(1);
  @$pb.TagNumber(2)
  set loras($core.List<$core.int> value) => $_setBytes(1, value);
  @$pb.TagNumber(2)
  $core.bool hasLoras() => $_has(1);
  @$pb.TagNumber(2)
  void clearLoras() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.List<$core.int> get controlNets => $_getN(2);
  @$pb.TagNumber(3)
  set controlNets($core.List<$core.int> value) => $_setBytes(2, value);
  @$pb.TagNumber(3)
  $core.bool hasControlNets() => $_has(2);
  @$pb.TagNumber(3)
  void clearControlNets() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.List<$core.int> get textualInversions => $_getN(3);
  @$pb.TagNumber(4)
  set textualInversions($core.List<$core.int> value) => $_setBytes(3, value);
  @$pb.TagNumber(4)
  $core.bool hasTextualInversions() => $_has(3);
  @$pb.TagNumber(4)
  void clearTextualInversions() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.List<$core.int> get upscalers => $_getN(4);
  @$pb.TagNumber(5)
  set upscalers($core.List<$core.int> value) => $_setBytes(4, value);
  @$pb.TagNumber(5)
  $core.bool hasUpscalers() => $_has(4);
  @$pb.TagNumber(5)
  void clearUpscalers() => $_clearField(5);
}

/// parameters in this Request is exactly same as generate function in ImageGenerator
class ImageGenerationRequest extends $pb.GeneratedMessage {
  factory ImageGenerationRequest({
    $core.List<$core.int>? image,
    $core.int? scaleFactor,
    $core.List<$core.int>? mask,
    $core.Iterable<HintProto>? hints,
    $core.String? prompt,
    $core.String? negativePrompt,
    $core.List<$core.int>? configuration,
    MetadataOverride? override,
    $core.Iterable<$core.String>? keywords,
    $core.String? user,
    DeviceType? device,
    $core.Iterable<$core.List<$core.int>>? contents,
    $core.String? sharedSecret,
    $core.bool? chunked,
  }) {
    final result = create();
    if (image != null) result.image = image;
    if (scaleFactor != null) result.scaleFactor = scaleFactor;
    if (mask != null) result.mask = mask;
    if (hints != null) result.hints.addAll(hints);
    if (prompt != null) result.prompt = prompt;
    if (negativePrompt != null) result.negativePrompt = negativePrompt;
    if (configuration != null) result.configuration = configuration;
    if (override != null) result.override = override;
    if (keywords != null) result.keywords.addAll(keywords);
    if (user != null) result.user = user;
    if (device != null) result.device = device;
    if (contents != null) result.contents.addAll(contents);
    if (sharedSecret != null) result.sharedSecret = sharedSecret;
    if (chunked != null) result.chunked = chunked;
    return result;
  }

  ImageGenerationRequest._();

  factory ImageGenerationRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ImageGenerationRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ImageGenerationRequest',
      createEmptyInstance: create)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'image', $pb.PbFieldType.OY)
    ..aI(2, _omitFieldNames ? '' : 'scaleFactor', protoName: 'scaleFactor')
    ..a<$core.List<$core.int>>(
        3, _omitFieldNames ? '' : 'mask', $pb.PbFieldType.OY)
    ..pPM<HintProto>(4, _omitFieldNames ? '' : 'hints',
        subBuilder: HintProto.create)
    ..aOS(5, _omitFieldNames ? '' : 'prompt')
    ..aOS(6, _omitFieldNames ? '' : 'negativePrompt',
        protoName: 'negativePrompt')
    ..a<$core.List<$core.int>>(
        7, _omitFieldNames ? '' : 'configuration', $pb.PbFieldType.OY)
    ..aOM<MetadataOverride>(8, _omitFieldNames ? '' : 'override',
        subBuilder: MetadataOverride.create)
    ..pPS(9, _omitFieldNames ? '' : 'keywords')
    ..aOS(10, _omitFieldNames ? '' : 'user')
    ..aE<DeviceType>(11, _omitFieldNames ? '' : 'device',
        enumValues: DeviceType.values)
    ..p<$core.List<$core.int>>(
        12, _omitFieldNames ? '' : 'contents', $pb.PbFieldType.PY)
    ..aOS(13, _omitFieldNames ? '' : 'sharedSecret', protoName: 'sharedSecret')
    ..aOB(14, _omitFieldNames ? '' : 'chunked')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ImageGenerationRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ImageGenerationRequest copyWith(
          void Function(ImageGenerationRequest) updates) =>
      super.copyWith((message) => updates(message as ImageGenerationRequest))
          as ImageGenerationRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ImageGenerationRequest create() => ImageGenerationRequest._();
  @$core.override
  ImageGenerationRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ImageGenerationRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ImageGenerationRequest>(create);
  static ImageGenerationRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get image => $_getN(0);
  @$pb.TagNumber(1)
  set image($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasImage() => $_has(0);
  @$pb.TagNumber(1)
  void clearImage() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get scaleFactor => $_getIZ(1);
  @$pb.TagNumber(2)
  set scaleFactor($core.int value) => $_setSignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasScaleFactor() => $_has(1);
  @$pb.TagNumber(2)
  void clearScaleFactor() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.List<$core.int> get mask => $_getN(2);
  @$pb.TagNumber(3)
  set mask($core.List<$core.int> value) => $_setBytes(2, value);
  @$pb.TagNumber(3)
  $core.bool hasMask() => $_has(2);
  @$pb.TagNumber(3)
  void clearMask() => $_clearField(3);

  @$pb.TagNumber(4)
  $pb.PbList<HintProto> get hints => $_getList(3);

  @$pb.TagNumber(5)
  $core.String get prompt => $_getSZ(4);
  @$pb.TagNumber(5)
  set prompt($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasPrompt() => $_has(4);
  @$pb.TagNumber(5)
  void clearPrompt() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.String get negativePrompt => $_getSZ(5);
  @$pb.TagNumber(6)
  set negativePrompt($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasNegativePrompt() => $_has(5);
  @$pb.TagNumber(6)
  void clearNegativePrompt() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.List<$core.int> get configuration => $_getN(6);
  @$pb.TagNumber(7)
  set configuration($core.List<$core.int> value) => $_setBytes(6, value);
  @$pb.TagNumber(7)
  $core.bool hasConfiguration() => $_has(6);
  @$pb.TagNumber(7)
  void clearConfiguration() => $_clearField(7);

  @$pb.TagNumber(8)
  MetadataOverride get override => $_getN(7);
  @$pb.TagNumber(8)
  set override(MetadataOverride value) => $_setField(8, value);
  @$pb.TagNumber(8)
  $core.bool hasOverride() => $_has(7);
  @$pb.TagNumber(8)
  void clearOverride() => $_clearField(8);
  @$pb.TagNumber(8)
  MetadataOverride ensureOverride() => $_ensure(7);

  @$pb.TagNumber(9)
  $pb.PbList<$core.String> get keywords => $_getList(8);

  @$pb.TagNumber(10)
  $core.String get user => $_getSZ(9);
  @$pb.TagNumber(10)
  set user($core.String value) => $_setString(9, value);
  @$pb.TagNumber(10)
  $core.bool hasUser() => $_has(9);
  @$pb.TagNumber(10)
  void clearUser() => $_clearField(10);

  @$pb.TagNumber(11)
  DeviceType get device => $_getN(10);
  @$pb.TagNumber(11)
  set device(DeviceType value) => $_setField(11, value);
  @$pb.TagNumber(11)
  $core.bool hasDevice() => $_has(10);
  @$pb.TagNumber(11)
  void clearDevice() => $_clearField(11);

  @$pb.TagNumber(12)
  $pb.PbList<$core.List<$core.int>> get contents => $_getList(11);

  @$pb.TagNumber(13)
  $core.String get sharedSecret => $_getSZ(12);
  @$pb.TagNumber(13)
  set sharedSecret($core.String value) => $_setString(12, value);
  @$pb.TagNumber(13)
  $core.bool hasSharedSecret() => $_has(12);
  @$pb.TagNumber(13)
  void clearSharedSecret() => $_clearField(13);

  @$pb.TagNumber(14)
  $core.bool get chunked => $_getBF(13);
  @$pb.TagNumber(14)
  set chunked($core.bool value) => $_setBool(13, value);
  @$pb.TagNumber(14)
  $core.bool hasChunked() => $_has(13);
  @$pb.TagNumber(14)
  void clearChunked() => $_clearField(14);
}

class HintProto extends $pb.GeneratedMessage {
  factory HintProto({
    $core.String? hintType,
    $core.Iterable<TensorAndWeight>? tensors,
  }) {
    final result = create();
    if (hintType != null) result.hintType = hintType;
    if (tensors != null) result.tensors.addAll(tensors);
    return result;
  }

  HintProto._();

  factory HintProto.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory HintProto.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'HintProto',
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'hintType', protoName: 'hintType')
    ..pPM<TensorAndWeight>(2, _omitFieldNames ? '' : 'tensors',
        subBuilder: TensorAndWeight.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  HintProto clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  HintProto copyWith(void Function(HintProto) updates) =>
      super.copyWith((message) => updates(message as HintProto)) as HintProto;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static HintProto create() => HintProto._();
  @$core.override
  HintProto createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static HintProto getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<HintProto>(create);
  static HintProto? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get hintType => $_getSZ(0);
  @$pb.TagNumber(1)
  set hintType($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasHintType() => $_has(0);
  @$pb.TagNumber(1)
  void clearHintType() => $_clearField(1);

  @$pb.TagNumber(2)
  $pb.PbList<TensorAndWeight> get tensors => $_getList(1);
}

/// Message to store each tensor and its associated float score
class TensorAndWeight extends $pb.GeneratedMessage {
  factory TensorAndWeight({
    $core.List<$core.int>? tensor,
    $core.double? weight,
  }) {
    final result = create();
    if (tensor != null) result.tensor = tensor;
    if (weight != null) result.weight = weight;
    return result;
  }

  TensorAndWeight._();

  factory TensorAndWeight.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory TensorAndWeight.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'TensorAndWeight',
      createEmptyInstance: create)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'tensor', $pb.PbFieldType.OY)
    ..aD(2, _omitFieldNames ? '' : 'weight', fieldType: $pb.PbFieldType.OF)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TensorAndWeight clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TensorAndWeight copyWith(void Function(TensorAndWeight) updates) =>
      super.copyWith((message) => updates(message as TensorAndWeight))
          as TensorAndWeight;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static TensorAndWeight create() => TensorAndWeight._();
  @$core.override
  TensorAndWeight createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static TensorAndWeight getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<TensorAndWeight>(create);
  static TensorAndWeight? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get tensor => $_getN(0);
  @$pb.TagNumber(1)
  set tensor($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasTensor() => $_has(0);
  @$pb.TagNumber(1)
  void clearTensor() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.double get weight => $_getN(1);
  @$pb.TagNumber(2)
  set weight($core.double value) => $_setFloat(1, value);
  @$pb.TagNumber(2)
  $core.bool hasWeight() => $_has(1);
  @$pb.TagNumber(2)
  void clearWeight() => $_clearField(2);
}

class ImageGenerationSignpostProto_TextEncoded extends $pb.GeneratedMessage {
  factory ImageGenerationSignpostProto_TextEncoded() => create();

  ImageGenerationSignpostProto_TextEncoded._();

  factory ImageGenerationSignpostProto_TextEncoded.fromBuffer(
          $core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ImageGenerationSignpostProto_TextEncoded.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ImageGenerationSignpostProto.TextEncoded',
      createEmptyInstance: create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ImageGenerationSignpostProto_TextEncoded clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ImageGenerationSignpostProto_TextEncoded copyWith(
          void Function(ImageGenerationSignpostProto_TextEncoded) updates) =>
      super.copyWith((message) =>
              updates(message as ImageGenerationSignpostProto_TextEncoded))
          as ImageGenerationSignpostProto_TextEncoded;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ImageGenerationSignpostProto_TextEncoded create() =>
      ImageGenerationSignpostProto_TextEncoded._();
  @$core.override
  ImageGenerationSignpostProto_TextEncoded createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ImageGenerationSignpostProto_TextEncoded getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<
          ImageGenerationSignpostProto_TextEncoded>(create);
  static ImageGenerationSignpostProto_TextEncoded? _defaultInstance;
}

class ImageGenerationSignpostProto_ImageEncoded extends $pb.GeneratedMessage {
  factory ImageGenerationSignpostProto_ImageEncoded() => create();

  ImageGenerationSignpostProto_ImageEncoded._();

  factory ImageGenerationSignpostProto_ImageEncoded.fromBuffer(
          $core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ImageGenerationSignpostProto_ImageEncoded.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ImageGenerationSignpostProto.ImageEncoded',
      createEmptyInstance: create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ImageGenerationSignpostProto_ImageEncoded clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ImageGenerationSignpostProto_ImageEncoded copyWith(
          void Function(ImageGenerationSignpostProto_ImageEncoded) updates) =>
      super.copyWith((message) =>
              updates(message as ImageGenerationSignpostProto_ImageEncoded))
          as ImageGenerationSignpostProto_ImageEncoded;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ImageGenerationSignpostProto_ImageEncoded create() =>
      ImageGenerationSignpostProto_ImageEncoded._();
  @$core.override
  ImageGenerationSignpostProto_ImageEncoded createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ImageGenerationSignpostProto_ImageEncoded getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<
          ImageGenerationSignpostProto_ImageEncoded>(create);
  static ImageGenerationSignpostProto_ImageEncoded? _defaultInstance;
}

class ImageGenerationSignpostProto_Sampling extends $pb.GeneratedMessage {
  factory ImageGenerationSignpostProto_Sampling({
    $core.int? step,
  }) {
    final result = create();
    if (step != null) result.step = step;
    return result;
  }

  ImageGenerationSignpostProto_Sampling._();

  factory ImageGenerationSignpostProto_Sampling.fromBuffer(
          $core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ImageGenerationSignpostProto_Sampling.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ImageGenerationSignpostProto.Sampling',
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'step')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ImageGenerationSignpostProto_Sampling clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ImageGenerationSignpostProto_Sampling copyWith(
          void Function(ImageGenerationSignpostProto_Sampling) updates) =>
      super.copyWith((message) =>
              updates(message as ImageGenerationSignpostProto_Sampling))
          as ImageGenerationSignpostProto_Sampling;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ImageGenerationSignpostProto_Sampling create() =>
      ImageGenerationSignpostProto_Sampling._();
  @$core.override
  ImageGenerationSignpostProto_Sampling createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ImageGenerationSignpostProto_Sampling getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<
          ImageGenerationSignpostProto_Sampling>(create);
  static ImageGenerationSignpostProto_Sampling? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get step => $_getIZ(0);
  @$pb.TagNumber(1)
  set step($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasStep() => $_has(0);
  @$pb.TagNumber(1)
  void clearStep() => $_clearField(1);
}

class ImageGenerationSignpostProto_ImageDecoded extends $pb.GeneratedMessage {
  factory ImageGenerationSignpostProto_ImageDecoded() => create();

  ImageGenerationSignpostProto_ImageDecoded._();

  factory ImageGenerationSignpostProto_ImageDecoded.fromBuffer(
          $core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ImageGenerationSignpostProto_ImageDecoded.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ImageGenerationSignpostProto.ImageDecoded',
      createEmptyInstance: create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ImageGenerationSignpostProto_ImageDecoded clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ImageGenerationSignpostProto_ImageDecoded copyWith(
          void Function(ImageGenerationSignpostProto_ImageDecoded) updates) =>
      super.copyWith((message) =>
              updates(message as ImageGenerationSignpostProto_ImageDecoded))
          as ImageGenerationSignpostProto_ImageDecoded;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ImageGenerationSignpostProto_ImageDecoded create() =>
      ImageGenerationSignpostProto_ImageDecoded._();
  @$core.override
  ImageGenerationSignpostProto_ImageDecoded createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ImageGenerationSignpostProto_ImageDecoded getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<
          ImageGenerationSignpostProto_ImageDecoded>(create);
  static ImageGenerationSignpostProto_ImageDecoded? _defaultInstance;
}

class ImageGenerationSignpostProto_SecondPassImageEncoded
    extends $pb.GeneratedMessage {
  factory ImageGenerationSignpostProto_SecondPassImageEncoded() => create();

  ImageGenerationSignpostProto_SecondPassImageEncoded._();

  factory ImageGenerationSignpostProto_SecondPassImageEncoded.fromBuffer(
          $core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ImageGenerationSignpostProto_SecondPassImageEncoded.fromJson(
          $core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames
          ? ''
          : 'ImageGenerationSignpostProto.SecondPassImageEncoded',
      createEmptyInstance: create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ImageGenerationSignpostProto_SecondPassImageEncoded clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ImageGenerationSignpostProto_SecondPassImageEncoded copyWith(
          void Function(ImageGenerationSignpostProto_SecondPassImageEncoded)
              updates) =>
      super.copyWith((message) => updates(
              message as ImageGenerationSignpostProto_SecondPassImageEncoded))
          as ImageGenerationSignpostProto_SecondPassImageEncoded;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ImageGenerationSignpostProto_SecondPassImageEncoded create() =>
      ImageGenerationSignpostProto_SecondPassImageEncoded._();
  @$core.override
  ImageGenerationSignpostProto_SecondPassImageEncoded createEmptyInstance() =>
      create();
  @$core.pragma('dart2js:noInline')
  static ImageGenerationSignpostProto_SecondPassImageEncoded getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<
          ImageGenerationSignpostProto_SecondPassImageEncoded>(create);
  static ImageGenerationSignpostProto_SecondPassImageEncoded? _defaultInstance;
}

class ImageGenerationSignpostProto_SecondPassSampling
    extends $pb.GeneratedMessage {
  factory ImageGenerationSignpostProto_SecondPassSampling({
    $core.int? step,
  }) {
    final result = create();
    if (step != null) result.step = step;
    return result;
  }

  ImageGenerationSignpostProto_SecondPassSampling._();

  factory ImageGenerationSignpostProto_SecondPassSampling.fromBuffer(
          $core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ImageGenerationSignpostProto_SecondPassSampling.fromJson(
          $core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames
          ? ''
          : 'ImageGenerationSignpostProto.SecondPassSampling',
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'step')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ImageGenerationSignpostProto_SecondPassSampling clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ImageGenerationSignpostProto_SecondPassSampling copyWith(
          void Function(ImageGenerationSignpostProto_SecondPassSampling)
              updates) =>
      super.copyWith((message) => updates(
              message as ImageGenerationSignpostProto_SecondPassSampling))
          as ImageGenerationSignpostProto_SecondPassSampling;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ImageGenerationSignpostProto_SecondPassSampling create() =>
      ImageGenerationSignpostProto_SecondPassSampling._();
  @$core.override
  ImageGenerationSignpostProto_SecondPassSampling createEmptyInstance() =>
      create();
  @$core.pragma('dart2js:noInline')
  static ImageGenerationSignpostProto_SecondPassSampling getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<
          ImageGenerationSignpostProto_SecondPassSampling>(create);
  static ImageGenerationSignpostProto_SecondPassSampling? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get step => $_getIZ(0);
  @$pb.TagNumber(1)
  set step($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasStep() => $_has(0);
  @$pb.TagNumber(1)
  void clearStep() => $_clearField(1);
}

class ImageGenerationSignpostProto_SecondPassImageDecoded
    extends $pb.GeneratedMessage {
  factory ImageGenerationSignpostProto_SecondPassImageDecoded() => create();

  ImageGenerationSignpostProto_SecondPassImageDecoded._();

  factory ImageGenerationSignpostProto_SecondPassImageDecoded.fromBuffer(
          $core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ImageGenerationSignpostProto_SecondPassImageDecoded.fromJson(
          $core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames
          ? ''
          : 'ImageGenerationSignpostProto.SecondPassImageDecoded',
      createEmptyInstance: create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ImageGenerationSignpostProto_SecondPassImageDecoded clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ImageGenerationSignpostProto_SecondPassImageDecoded copyWith(
          void Function(ImageGenerationSignpostProto_SecondPassImageDecoded)
              updates) =>
      super.copyWith((message) => updates(
              message as ImageGenerationSignpostProto_SecondPassImageDecoded))
          as ImageGenerationSignpostProto_SecondPassImageDecoded;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ImageGenerationSignpostProto_SecondPassImageDecoded create() =>
      ImageGenerationSignpostProto_SecondPassImageDecoded._();
  @$core.override
  ImageGenerationSignpostProto_SecondPassImageDecoded createEmptyInstance() =>
      create();
  @$core.pragma('dart2js:noInline')
  static ImageGenerationSignpostProto_SecondPassImageDecoded getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<
          ImageGenerationSignpostProto_SecondPassImageDecoded>(create);
  static ImageGenerationSignpostProto_SecondPassImageDecoded? _defaultInstance;
}

class ImageGenerationSignpostProto_FaceRestored extends $pb.GeneratedMessage {
  factory ImageGenerationSignpostProto_FaceRestored() => create();

  ImageGenerationSignpostProto_FaceRestored._();

  factory ImageGenerationSignpostProto_FaceRestored.fromBuffer(
          $core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ImageGenerationSignpostProto_FaceRestored.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ImageGenerationSignpostProto.FaceRestored',
      createEmptyInstance: create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ImageGenerationSignpostProto_FaceRestored clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ImageGenerationSignpostProto_FaceRestored copyWith(
          void Function(ImageGenerationSignpostProto_FaceRestored) updates) =>
      super.copyWith((message) =>
              updates(message as ImageGenerationSignpostProto_FaceRestored))
          as ImageGenerationSignpostProto_FaceRestored;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ImageGenerationSignpostProto_FaceRestored create() =>
      ImageGenerationSignpostProto_FaceRestored._();
  @$core.override
  ImageGenerationSignpostProto_FaceRestored createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ImageGenerationSignpostProto_FaceRestored getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<
          ImageGenerationSignpostProto_FaceRestored>(create);
  static ImageGenerationSignpostProto_FaceRestored? _defaultInstance;
}

class ImageGenerationSignpostProto_ImageUpscaled extends $pb.GeneratedMessage {
  factory ImageGenerationSignpostProto_ImageUpscaled() => create();

  ImageGenerationSignpostProto_ImageUpscaled._();

  factory ImageGenerationSignpostProto_ImageUpscaled.fromBuffer(
          $core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ImageGenerationSignpostProto_ImageUpscaled.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ImageGenerationSignpostProto.ImageUpscaled',
      createEmptyInstance: create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ImageGenerationSignpostProto_ImageUpscaled clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ImageGenerationSignpostProto_ImageUpscaled copyWith(
          void Function(ImageGenerationSignpostProto_ImageUpscaled) updates) =>
      super.copyWith((message) =>
              updates(message as ImageGenerationSignpostProto_ImageUpscaled))
          as ImageGenerationSignpostProto_ImageUpscaled;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ImageGenerationSignpostProto_ImageUpscaled create() =>
      ImageGenerationSignpostProto_ImageUpscaled._();
  @$core.override
  ImageGenerationSignpostProto_ImageUpscaled createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ImageGenerationSignpostProto_ImageUpscaled getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<
          ImageGenerationSignpostProto_ImageUpscaled>(create);
  static ImageGenerationSignpostProto_ImageUpscaled? _defaultInstance;
}

enum ImageGenerationSignpostProto_Signpost {
  textEncoded,
  imageEncoded,
  sampling,
  imageDecoded,
  secondPassImageEncoded,
  secondPassSampling,
  secondPassImageDecoded,
  faceRestored,
  imageUpscaled,
  notSet
}

class ImageGenerationSignpostProto extends $pb.GeneratedMessage {
  factory ImageGenerationSignpostProto({
    ImageGenerationSignpostProto_TextEncoded? textEncoded,
    ImageGenerationSignpostProto_ImageEncoded? imageEncoded,
    ImageGenerationSignpostProto_Sampling? sampling,
    ImageGenerationSignpostProto_ImageDecoded? imageDecoded,
    ImageGenerationSignpostProto_SecondPassImageEncoded? secondPassImageEncoded,
    ImageGenerationSignpostProto_SecondPassSampling? secondPassSampling,
    ImageGenerationSignpostProto_SecondPassImageDecoded? secondPassImageDecoded,
    ImageGenerationSignpostProto_FaceRestored? faceRestored,
    ImageGenerationSignpostProto_ImageUpscaled? imageUpscaled,
  }) {
    final result = create();
    if (textEncoded != null) result.textEncoded = textEncoded;
    if (imageEncoded != null) result.imageEncoded = imageEncoded;
    if (sampling != null) result.sampling = sampling;
    if (imageDecoded != null) result.imageDecoded = imageDecoded;
    if (secondPassImageEncoded != null)
      result.secondPassImageEncoded = secondPassImageEncoded;
    if (secondPassSampling != null)
      result.secondPassSampling = secondPassSampling;
    if (secondPassImageDecoded != null)
      result.secondPassImageDecoded = secondPassImageDecoded;
    if (faceRestored != null) result.faceRestored = faceRestored;
    if (imageUpscaled != null) result.imageUpscaled = imageUpscaled;
    return result;
  }

  ImageGenerationSignpostProto._();

  factory ImageGenerationSignpostProto.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ImageGenerationSignpostProto.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static const $core.Map<$core.int, ImageGenerationSignpostProto_Signpost>
      _ImageGenerationSignpostProto_SignpostByTag = {
    1: ImageGenerationSignpostProto_Signpost.textEncoded,
    2: ImageGenerationSignpostProto_Signpost.imageEncoded,
    3: ImageGenerationSignpostProto_Signpost.sampling,
    4: ImageGenerationSignpostProto_Signpost.imageDecoded,
    5: ImageGenerationSignpostProto_Signpost.secondPassImageEncoded,
    6: ImageGenerationSignpostProto_Signpost.secondPassSampling,
    7: ImageGenerationSignpostProto_Signpost.secondPassImageDecoded,
    8: ImageGenerationSignpostProto_Signpost.faceRestored,
    9: ImageGenerationSignpostProto_Signpost.imageUpscaled,
    0: ImageGenerationSignpostProto_Signpost.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ImageGenerationSignpostProto',
      createEmptyInstance: create)
    ..oo(0, [1, 2, 3, 4, 5, 6, 7, 8, 9])
    ..aOM<ImageGenerationSignpostProto_TextEncoded>(
        1, _omitFieldNames ? '' : 'textEncoded',
        protoName: 'textEncoded',
        subBuilder: ImageGenerationSignpostProto_TextEncoded.create)
    ..aOM<ImageGenerationSignpostProto_ImageEncoded>(
        2, _omitFieldNames ? '' : 'imageEncoded',
        protoName: 'imageEncoded',
        subBuilder: ImageGenerationSignpostProto_ImageEncoded.create)
    ..aOM<ImageGenerationSignpostProto_Sampling>(
        3, _omitFieldNames ? '' : 'sampling',
        subBuilder: ImageGenerationSignpostProto_Sampling.create)
    ..aOM<ImageGenerationSignpostProto_ImageDecoded>(
        4, _omitFieldNames ? '' : 'imageDecoded',
        protoName: 'imageDecoded',
        subBuilder: ImageGenerationSignpostProto_ImageDecoded.create)
    ..aOM<ImageGenerationSignpostProto_SecondPassImageEncoded>(
        5, _omitFieldNames ? '' : 'secondPassImageEncoded',
        protoName: 'secondPassImageEncoded',
        subBuilder: ImageGenerationSignpostProto_SecondPassImageEncoded.create)
    ..aOM<ImageGenerationSignpostProto_SecondPassSampling>(
        6, _omitFieldNames ? '' : 'secondPassSampling',
        protoName: 'secondPassSampling',
        subBuilder: ImageGenerationSignpostProto_SecondPassSampling.create)
    ..aOM<ImageGenerationSignpostProto_SecondPassImageDecoded>(
        7, _omitFieldNames ? '' : 'secondPassImageDecoded',
        protoName: 'secondPassImageDecoded',
        subBuilder: ImageGenerationSignpostProto_SecondPassImageDecoded.create)
    ..aOM<ImageGenerationSignpostProto_FaceRestored>(
        8, _omitFieldNames ? '' : 'faceRestored',
        protoName: 'faceRestored',
        subBuilder: ImageGenerationSignpostProto_FaceRestored.create)
    ..aOM<ImageGenerationSignpostProto_ImageUpscaled>(
        9, _omitFieldNames ? '' : 'imageUpscaled',
        protoName: 'imageUpscaled',
        subBuilder: ImageGenerationSignpostProto_ImageUpscaled.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ImageGenerationSignpostProto clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ImageGenerationSignpostProto copyWith(
          void Function(ImageGenerationSignpostProto) updates) =>
      super.copyWith(
              (message) => updates(message as ImageGenerationSignpostProto))
          as ImageGenerationSignpostProto;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ImageGenerationSignpostProto create() =>
      ImageGenerationSignpostProto._();
  @$core.override
  ImageGenerationSignpostProto createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ImageGenerationSignpostProto getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ImageGenerationSignpostProto>(create);
  static ImageGenerationSignpostProto? _defaultInstance;

  @$pb.TagNumber(1)
  @$pb.TagNumber(2)
  @$pb.TagNumber(3)
  @$pb.TagNumber(4)
  @$pb.TagNumber(5)
  @$pb.TagNumber(6)
  @$pb.TagNumber(7)
  @$pb.TagNumber(8)
  @$pb.TagNumber(9)
  ImageGenerationSignpostProto_Signpost whichSignpost() =>
      _ImageGenerationSignpostProto_SignpostByTag[$_whichOneof(0)]!;
  @$pb.TagNumber(1)
  @$pb.TagNumber(2)
  @$pb.TagNumber(3)
  @$pb.TagNumber(4)
  @$pb.TagNumber(5)
  @$pb.TagNumber(6)
  @$pb.TagNumber(7)
  @$pb.TagNumber(8)
  @$pb.TagNumber(9)
  void clearSignpost() => $_clearField($_whichOneof(0));

  @$pb.TagNumber(1)
  ImageGenerationSignpostProto_TextEncoded get textEncoded => $_getN(0);
  @$pb.TagNumber(1)
  set textEncoded(ImageGenerationSignpostProto_TextEncoded value) =>
      $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasTextEncoded() => $_has(0);
  @$pb.TagNumber(1)
  void clearTextEncoded() => $_clearField(1);
  @$pb.TagNumber(1)
  ImageGenerationSignpostProto_TextEncoded ensureTextEncoded() => $_ensure(0);

  @$pb.TagNumber(2)
  ImageGenerationSignpostProto_ImageEncoded get imageEncoded => $_getN(1);
  @$pb.TagNumber(2)
  set imageEncoded(ImageGenerationSignpostProto_ImageEncoded value) =>
      $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasImageEncoded() => $_has(1);
  @$pb.TagNumber(2)
  void clearImageEncoded() => $_clearField(2);
  @$pb.TagNumber(2)
  ImageGenerationSignpostProto_ImageEncoded ensureImageEncoded() => $_ensure(1);

  @$pb.TagNumber(3)
  ImageGenerationSignpostProto_Sampling get sampling => $_getN(2);
  @$pb.TagNumber(3)
  set sampling(ImageGenerationSignpostProto_Sampling value) =>
      $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasSampling() => $_has(2);
  @$pb.TagNumber(3)
  void clearSampling() => $_clearField(3);
  @$pb.TagNumber(3)
  ImageGenerationSignpostProto_Sampling ensureSampling() => $_ensure(2);

  @$pb.TagNumber(4)
  ImageGenerationSignpostProto_ImageDecoded get imageDecoded => $_getN(3);
  @$pb.TagNumber(4)
  set imageDecoded(ImageGenerationSignpostProto_ImageDecoded value) =>
      $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasImageDecoded() => $_has(3);
  @$pb.TagNumber(4)
  void clearImageDecoded() => $_clearField(4);
  @$pb.TagNumber(4)
  ImageGenerationSignpostProto_ImageDecoded ensureImageDecoded() => $_ensure(3);

  @$pb.TagNumber(5)
  ImageGenerationSignpostProto_SecondPassImageEncoded
      get secondPassImageEncoded => $_getN(4);
  @$pb.TagNumber(5)
  set secondPassImageEncoded(
          ImageGenerationSignpostProto_SecondPassImageEncoded value) =>
      $_setField(5, value);
  @$pb.TagNumber(5)
  $core.bool hasSecondPassImageEncoded() => $_has(4);
  @$pb.TagNumber(5)
  void clearSecondPassImageEncoded() => $_clearField(5);
  @$pb.TagNumber(5)
  ImageGenerationSignpostProto_SecondPassImageEncoded
      ensureSecondPassImageEncoded() => $_ensure(4);

  @$pb.TagNumber(6)
  ImageGenerationSignpostProto_SecondPassSampling get secondPassSampling =>
      $_getN(5);
  @$pb.TagNumber(6)
  set secondPassSampling(
          ImageGenerationSignpostProto_SecondPassSampling value) =>
      $_setField(6, value);
  @$pb.TagNumber(6)
  $core.bool hasSecondPassSampling() => $_has(5);
  @$pb.TagNumber(6)
  void clearSecondPassSampling() => $_clearField(6);
  @$pb.TagNumber(6)
  ImageGenerationSignpostProto_SecondPassSampling ensureSecondPassSampling() =>
      $_ensure(5);

  @$pb.TagNumber(7)
  ImageGenerationSignpostProto_SecondPassImageDecoded
      get secondPassImageDecoded => $_getN(6);
  @$pb.TagNumber(7)
  set secondPassImageDecoded(
          ImageGenerationSignpostProto_SecondPassImageDecoded value) =>
      $_setField(7, value);
  @$pb.TagNumber(7)
  $core.bool hasSecondPassImageDecoded() => $_has(6);
  @$pb.TagNumber(7)
  void clearSecondPassImageDecoded() => $_clearField(7);
  @$pb.TagNumber(7)
  ImageGenerationSignpostProto_SecondPassImageDecoded
      ensureSecondPassImageDecoded() => $_ensure(6);

  @$pb.TagNumber(8)
  ImageGenerationSignpostProto_FaceRestored get faceRestored => $_getN(7);
  @$pb.TagNumber(8)
  set faceRestored(ImageGenerationSignpostProto_FaceRestored value) =>
      $_setField(8, value);
  @$pb.TagNumber(8)
  $core.bool hasFaceRestored() => $_has(7);
  @$pb.TagNumber(8)
  void clearFaceRestored() => $_clearField(8);
  @$pb.TagNumber(8)
  ImageGenerationSignpostProto_FaceRestored ensureFaceRestored() => $_ensure(7);

  @$pb.TagNumber(9)
  ImageGenerationSignpostProto_ImageUpscaled get imageUpscaled => $_getN(8);
  @$pb.TagNumber(9)
  set imageUpscaled(ImageGenerationSignpostProto_ImageUpscaled value) =>
      $_setField(9, value);
  @$pb.TagNumber(9)
  $core.bool hasImageUpscaled() => $_has(8);
  @$pb.TagNumber(9)
  void clearImageUpscaled() => $_clearField(9);
  @$pb.TagNumber(9)
  ImageGenerationSignpostProto_ImageUpscaled ensureImageUpscaled() =>
      $_ensure(8);
}

class RemoteDownloadResponse extends $pb.GeneratedMessage {
  factory RemoteDownloadResponse({
    $fixnum.Int64? bytesReceived,
    $fixnum.Int64? bytesExpected,
    $core.int? item,
    $core.int? itemsExpected,
    $core.String? tag,
  }) {
    final result = create();
    if (bytesReceived != null) result.bytesReceived = bytesReceived;
    if (bytesExpected != null) result.bytesExpected = bytesExpected;
    if (item != null) result.item = item;
    if (itemsExpected != null) result.itemsExpected = itemsExpected;
    if (tag != null) result.tag = tag;
    return result;
  }

  RemoteDownloadResponse._();

  factory RemoteDownloadResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory RemoteDownloadResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RemoteDownloadResponse',
      createEmptyInstance: create)
    ..aInt64(1, _omitFieldNames ? '' : 'bytesReceived',
        protoName: 'bytesReceived')
    ..aInt64(2, _omitFieldNames ? '' : 'bytesExpected',
        protoName: 'bytesExpected')
    ..aI(3, _omitFieldNames ? '' : 'item')
    ..aI(4, _omitFieldNames ? '' : 'itemsExpected', protoName: 'itemsExpected')
    ..aOS(5, _omitFieldNames ? '' : 'tag')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RemoteDownloadResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RemoteDownloadResponse copyWith(
          void Function(RemoteDownloadResponse) updates) =>
      super.copyWith((message) => updates(message as RemoteDownloadResponse))
          as RemoteDownloadResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static RemoteDownloadResponse create() => RemoteDownloadResponse._();
  @$core.override
  RemoteDownloadResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static RemoteDownloadResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<RemoteDownloadResponse>(create);
  static RemoteDownloadResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $fixnum.Int64 get bytesReceived => $_getI64(0);
  @$pb.TagNumber(1)
  set bytesReceived($fixnum.Int64 value) => $_setInt64(0, value);
  @$pb.TagNumber(1)
  $core.bool hasBytesReceived() => $_has(0);
  @$pb.TagNumber(1)
  void clearBytesReceived() => $_clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get bytesExpected => $_getI64(1);
  @$pb.TagNumber(2)
  set bytesExpected($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasBytesExpected() => $_has(1);
  @$pb.TagNumber(2)
  void clearBytesExpected() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get item => $_getIZ(2);
  @$pb.TagNumber(3)
  set item($core.int value) => $_setSignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasItem() => $_has(2);
  @$pb.TagNumber(3)
  void clearItem() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.int get itemsExpected => $_getIZ(3);
  @$pb.TagNumber(4)
  set itemsExpected($core.int value) => $_setSignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasItemsExpected() => $_has(3);
  @$pb.TagNumber(4)
  void clearItemsExpected() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get tag => $_getSZ(4);
  @$pb.TagNumber(5)
  set tag($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasTag() => $_has(4);
  @$pb.TagNumber(5)
  void clearTag() => $_clearField(5);
}

class ImageGenerationResponse extends $pb.GeneratedMessage {
  factory ImageGenerationResponse({
    $core.Iterable<$core.List<$core.int>>? generatedImages,
    ImageGenerationSignpostProto? currentSignpost,
    $core.Iterable<ImageGenerationSignpostProto>? signposts,
    $core.List<$core.int>? previewImage,
    $core.int? scaleFactor,
    $core.Iterable<$core.String>? tags,
    $fixnum.Int64? downloadSize,
    ChunkState? chunkState,
    RemoteDownloadResponse? remoteDownload,
    $core.Iterable<$core.List<$core.int>>? generatedAudio,
  }) {
    final result = create();
    if (generatedImages != null) result.generatedImages.addAll(generatedImages);
    if (currentSignpost != null) result.currentSignpost = currentSignpost;
    if (signposts != null) result.signposts.addAll(signposts);
    if (previewImage != null) result.previewImage = previewImage;
    if (scaleFactor != null) result.scaleFactor = scaleFactor;
    if (tags != null) result.tags.addAll(tags);
    if (downloadSize != null) result.downloadSize = downloadSize;
    if (chunkState != null) result.chunkState = chunkState;
    if (remoteDownload != null) result.remoteDownload = remoteDownload;
    if (generatedAudio != null) result.generatedAudio.addAll(generatedAudio);
    return result;
  }

  ImageGenerationResponse._();

  factory ImageGenerationResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ImageGenerationResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ImageGenerationResponse',
      createEmptyInstance: create)
    ..p<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'generatedImages', $pb.PbFieldType.PY,
        protoName: 'generatedImages')
    ..aOM<ImageGenerationSignpostProto>(
        2, _omitFieldNames ? '' : 'currentSignpost',
        protoName: 'currentSignpost',
        subBuilder: ImageGenerationSignpostProto.create)
    ..pPM<ImageGenerationSignpostProto>(3, _omitFieldNames ? '' : 'signposts',
        subBuilder: ImageGenerationSignpostProto.create)
    ..a<$core.List<$core.int>>(
        4, _omitFieldNames ? '' : 'previewImage', $pb.PbFieldType.OY,
        protoName: 'previewImage')
    ..aI(5, _omitFieldNames ? '' : 'scaleFactor', protoName: 'scaleFactor')
    ..pPS(6, _omitFieldNames ? '' : 'tags')
    ..aInt64(7, _omitFieldNames ? '' : 'downloadSize',
        protoName: 'downloadSize')
    ..aE<ChunkState>(8, _omitFieldNames ? '' : 'chunkState',
        protoName: 'chunkState', enumValues: ChunkState.values)
    ..aOM<RemoteDownloadResponse>(9, _omitFieldNames ? '' : 'remoteDownload',
        protoName: 'remoteDownload', subBuilder: RemoteDownloadResponse.create)
    ..p<$core.List<$core.int>>(
        10, _omitFieldNames ? '' : 'generatedAudio', $pb.PbFieldType.PY,
        protoName: 'generatedAudio')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ImageGenerationResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ImageGenerationResponse copyWith(
          void Function(ImageGenerationResponse) updates) =>
      super.copyWith((message) => updates(message as ImageGenerationResponse))
          as ImageGenerationResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ImageGenerationResponse create() => ImageGenerationResponse._();
  @$core.override
  ImageGenerationResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ImageGenerationResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ImageGenerationResponse>(create);
  static ImageGenerationResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<$core.List<$core.int>> get generatedImages => $_getList(0);

  @$pb.TagNumber(2)
  ImageGenerationSignpostProto get currentSignpost => $_getN(1);
  @$pb.TagNumber(2)
  set currentSignpost(ImageGenerationSignpostProto value) =>
      $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasCurrentSignpost() => $_has(1);
  @$pb.TagNumber(2)
  void clearCurrentSignpost() => $_clearField(2);
  @$pb.TagNumber(2)
  ImageGenerationSignpostProto ensureCurrentSignpost() => $_ensure(1);

  @$pb.TagNumber(3)
  $pb.PbList<ImageGenerationSignpostProto> get signposts => $_getList(2);

  @$pb.TagNumber(4)
  $core.List<$core.int> get previewImage => $_getN(3);
  @$pb.TagNumber(4)
  set previewImage($core.List<$core.int> value) => $_setBytes(3, value);
  @$pb.TagNumber(4)
  $core.bool hasPreviewImage() => $_has(3);
  @$pb.TagNumber(4)
  void clearPreviewImage() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.int get scaleFactor => $_getIZ(4);
  @$pb.TagNumber(5)
  set scaleFactor($core.int value) => $_setSignedInt32(4, value);
  @$pb.TagNumber(5)
  $core.bool hasScaleFactor() => $_has(4);
  @$pb.TagNumber(5)
  void clearScaleFactor() => $_clearField(5);

  @$pb.TagNumber(6)
  $pb.PbList<$core.String> get tags => $_getList(5);

  @$pb.TagNumber(7)
  $fixnum.Int64 get downloadSize => $_getI64(6);
  @$pb.TagNumber(7)
  set downloadSize($fixnum.Int64 value) => $_setInt64(6, value);
  @$pb.TagNumber(7)
  $core.bool hasDownloadSize() => $_has(6);
  @$pb.TagNumber(7)
  void clearDownloadSize() => $_clearField(7);

  @$pb.TagNumber(8)
  ChunkState get chunkState => $_getN(7);
  @$pb.TagNumber(8)
  set chunkState(ChunkState value) => $_setField(8, value);
  @$pb.TagNumber(8)
  $core.bool hasChunkState() => $_has(7);
  @$pb.TagNumber(8)
  void clearChunkState() => $_clearField(8);

  @$pb.TagNumber(9)
  RemoteDownloadResponse get remoteDownload => $_getN(8);
  @$pb.TagNumber(9)
  set remoteDownload(RemoteDownloadResponse value) => $_setField(9, value);
  @$pb.TagNumber(9)
  $core.bool hasRemoteDownload() => $_has(8);
  @$pb.TagNumber(9)
  void clearRemoteDownload() => $_clearField(9);
  @$pb.TagNumber(9)
  RemoteDownloadResponse ensureRemoteDownload() => $_ensure(8);

  @$pb.TagNumber(10)
  $pb.PbList<$core.List<$core.int>> get generatedAudio => $_getList(9);
}

class FileChunk extends $pb.GeneratedMessage {
  factory FileChunk({
    $core.List<$core.int>? content,
    $core.String? filename,
    $fixnum.Int64? offset,
  }) {
    final result = create();
    if (content != null) result.content = content;
    if (filename != null) result.filename = filename;
    if (offset != null) result.offset = offset;
    return result;
  }

  FileChunk._();

  factory FileChunk.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory FileChunk.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'FileChunk',
      createEmptyInstance: create)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'content', $pb.PbFieldType.OY)
    ..aOS(2, _omitFieldNames ? '' : 'filename')
    ..aInt64(3, _omitFieldNames ? '' : 'offset')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FileChunk clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FileChunk copyWith(void Function(FileChunk) updates) =>
      super.copyWith((message) => updates(message as FileChunk)) as FileChunk;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static FileChunk create() => FileChunk._();
  @$core.override
  FileChunk createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static FileChunk getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<FileChunk>(create);
  static FileChunk? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get content => $_getN(0);
  @$pb.TagNumber(1)
  set content($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasContent() => $_has(0);
  @$pb.TagNumber(1)
  void clearContent() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get filename => $_getSZ(1);
  @$pb.TagNumber(2)
  set filename($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasFilename() => $_has(1);
  @$pb.TagNumber(2)
  void clearFilename() => $_clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get offset => $_getI64(2);
  @$pb.TagNumber(3)
  set offset($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(3)
  $core.bool hasOffset() => $_has(2);
  @$pb.TagNumber(3)
  void clearOffset() => $_clearField(3);
}

class InitUploadRequest extends $pb.GeneratedMessage {
  factory InitUploadRequest({
    $core.String? filename,
    $core.List<$core.int>? sha256,
    $fixnum.Int64? totalSize,
  }) {
    final result = create();
    if (filename != null) result.filename = filename;
    if (sha256 != null) result.sha256 = sha256;
    if (totalSize != null) result.totalSize = totalSize;
    return result;
  }

  InitUploadRequest._();

  factory InitUploadRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory InitUploadRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'InitUploadRequest',
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'filename')
    ..a<$core.List<$core.int>>(
        2, _omitFieldNames ? '' : 'sha256', $pb.PbFieldType.OY)
    ..aInt64(3, _omitFieldNames ? '' : 'totalSize', protoName: 'totalSize')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  InitUploadRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  InitUploadRequest copyWith(void Function(InitUploadRequest) updates) =>
      super.copyWith((message) => updates(message as InitUploadRequest))
          as InitUploadRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static InitUploadRequest create() => InitUploadRequest._();
  @$core.override
  InitUploadRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static InitUploadRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<InitUploadRequest>(create);
  static InitUploadRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get filename => $_getSZ(0);
  @$pb.TagNumber(1)
  set filename($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasFilename() => $_has(0);
  @$pb.TagNumber(1)
  void clearFilename() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get sha256 => $_getN(1);
  @$pb.TagNumber(2)
  set sha256($core.List<$core.int> value) => $_setBytes(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSha256() => $_has(1);
  @$pb.TagNumber(2)
  void clearSha256() => $_clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get totalSize => $_getI64(2);
  @$pb.TagNumber(3)
  set totalSize($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(3)
  $core.bool hasTotalSize() => $_has(2);
  @$pb.TagNumber(3)
  void clearTotalSize() => $_clearField(3);
}

class UploadResponse extends $pb.GeneratedMessage {
  factory UploadResponse({
    $core.bool? chunkUploadSuccess,
    $fixnum.Int64? receivedOffset,
    $core.String? message,
    $core.String? filename,
  }) {
    final result = create();
    if (chunkUploadSuccess != null)
      result.chunkUploadSuccess = chunkUploadSuccess;
    if (receivedOffset != null) result.receivedOffset = receivedOffset;
    if (message != null) result.message = message;
    if (filename != null) result.filename = filename;
    return result;
  }

  UploadResponse._();

  factory UploadResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory UploadResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'UploadResponse',
      createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'chunkUploadSuccess',
        protoName: 'chunkUploadSuccess')
    ..aInt64(2, _omitFieldNames ? '' : 'receivedOffset',
        protoName: 'receivedOffset')
    ..aOS(3, _omitFieldNames ? '' : 'message')
    ..aOS(4, _omitFieldNames ? '' : 'filename')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UploadResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UploadResponse copyWith(void Function(UploadResponse) updates) =>
      super.copyWith((message) => updates(message as UploadResponse))
          as UploadResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static UploadResponse create() => UploadResponse._();
  @$core.override
  UploadResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static UploadResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<UploadResponse>(create);
  static UploadResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get chunkUploadSuccess => $_getBF(0);
  @$pb.TagNumber(1)
  set chunkUploadSuccess($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasChunkUploadSuccess() => $_has(0);
  @$pb.TagNumber(1)
  void clearChunkUploadSuccess() => $_clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get receivedOffset => $_getI64(1);
  @$pb.TagNumber(2)
  set receivedOffset($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasReceivedOffset() => $_has(1);
  @$pb.TagNumber(2)
  void clearReceivedOffset() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get message => $_getSZ(2);
  @$pb.TagNumber(3)
  set message($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasMessage() => $_has(2);
  @$pb.TagNumber(3)
  void clearMessage() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get filename => $_getSZ(3);
  @$pb.TagNumber(4)
  set filename($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasFilename() => $_has(3);
  @$pb.TagNumber(4)
  void clearFilename() => $_clearField(4);
}

enum FileUploadRequest_Request { initRequest, chunk, notSet }

/// Union type for either an InitUploadRequest or FileChunk.
class FileUploadRequest extends $pb.GeneratedMessage {
  factory FileUploadRequest({
    InitUploadRequest? initRequest,
    FileChunk? chunk,
    $core.String? sharedSecret,
  }) {
    final result = create();
    if (initRequest != null) result.initRequest = initRequest;
    if (chunk != null) result.chunk = chunk;
    if (sharedSecret != null) result.sharedSecret = sharedSecret;
    return result;
  }

  FileUploadRequest._();

  factory FileUploadRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory FileUploadRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static const $core.Map<$core.int, FileUploadRequest_Request>
      _FileUploadRequest_RequestByTag = {
    1: FileUploadRequest_Request.initRequest,
    2: FileUploadRequest_Request.chunk,
    0: FileUploadRequest_Request.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'FileUploadRequest',
      createEmptyInstance: create)
    ..oo(0, [1, 2])
    ..aOM<InitUploadRequest>(1, _omitFieldNames ? '' : 'initRequest',
        protoName: 'initRequest', subBuilder: InitUploadRequest.create)
    ..aOM<FileChunk>(2, _omitFieldNames ? '' : 'chunk',
        subBuilder: FileChunk.create)
    ..aOS(3, _omitFieldNames ? '' : 'sharedSecret', protoName: 'sharedSecret')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FileUploadRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FileUploadRequest copyWith(void Function(FileUploadRequest) updates) =>
      super.copyWith((message) => updates(message as FileUploadRequest))
          as FileUploadRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static FileUploadRequest create() => FileUploadRequest._();
  @$core.override
  FileUploadRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static FileUploadRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<FileUploadRequest>(create);
  static FileUploadRequest? _defaultInstance;

  @$pb.TagNumber(1)
  @$pb.TagNumber(2)
  FileUploadRequest_Request whichRequest() =>
      _FileUploadRequest_RequestByTag[$_whichOneof(0)]!;
  @$pb.TagNumber(1)
  @$pb.TagNumber(2)
  void clearRequest() => $_clearField($_whichOneof(0));

  @$pb.TagNumber(1)
  InitUploadRequest get initRequest => $_getN(0);
  @$pb.TagNumber(1)
  set initRequest(InitUploadRequest value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasInitRequest() => $_has(0);
  @$pb.TagNumber(1)
  void clearInitRequest() => $_clearField(1);
  @$pb.TagNumber(1)
  InitUploadRequest ensureInitRequest() => $_ensure(0);

  @$pb.TagNumber(2)
  FileChunk get chunk => $_getN(1);
  @$pb.TagNumber(2)
  set chunk(FileChunk value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasChunk() => $_has(1);
  @$pb.TagNumber(2)
  void clearChunk() => $_clearField(2);
  @$pb.TagNumber(2)
  FileChunk ensureChunk() => $_ensure(1);

  @$pb.TagNumber(3)
  $core.String get sharedSecret => $_getSZ(2);
  @$pb.TagNumber(3)
  set sharedSecret($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasSharedSecret() => $_has(2);
  @$pb.TagNumber(3)
  void clearSharedSecret() => $_clearField(3);
}

class PubkeyRequest extends $pb.GeneratedMessage {
  factory PubkeyRequest({
    $core.String? name,
  }) {
    final result = create();
    if (name != null) result.name = name;
    return result;
  }

  PubkeyRequest._();

  factory PubkeyRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory PubkeyRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'PubkeyRequest',
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'name')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PubkeyRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PubkeyRequest copyWith(void Function(PubkeyRequest) updates) =>
      super.copyWith((message) => updates(message as PubkeyRequest))
          as PubkeyRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PubkeyRequest create() => PubkeyRequest._();
  @$core.override
  PubkeyRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static PubkeyRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<PubkeyRequest>(create);
  static PubkeyRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get name => $_getSZ(0);
  @$pb.TagNumber(1)
  set name($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasName() => $_has(0);
  @$pb.TagNumber(1)
  void clearName() => $_clearField(1);
}

class PubkeyResponse extends $pb.GeneratedMessage {
  factory PubkeyResponse({
    $core.String? message,
    $core.String? pubkey,
  }) {
    final result = create();
    if (message != null) result.message = message;
    if (pubkey != null) result.pubkey = pubkey;
    return result;
  }

  PubkeyResponse._();

  factory PubkeyResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory PubkeyResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'PubkeyResponse',
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'message')
    ..aOS(2, _omitFieldNames ? '' : 'pubkey')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PubkeyResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PubkeyResponse copyWith(void Function(PubkeyResponse) updates) =>
      super.copyWith((message) => updates(message as PubkeyResponse))
          as PubkeyResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PubkeyResponse create() => PubkeyResponse._();
  @$core.override
  PubkeyResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static PubkeyResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<PubkeyResponse>(create);
  static PubkeyResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get message => $_getSZ(0);
  @$pb.TagNumber(1)
  set message($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasMessage() => $_has(0);
  @$pb.TagNumber(1)
  void clearMessage() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get pubkey => $_getSZ(1);
  @$pb.TagNumber(2)
  set pubkey($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasPubkey() => $_has(1);
  @$pb.TagNumber(2)
  void clearPubkey() => $_clearField(2);
}

class HoursRequest extends $pb.GeneratedMessage {
  factory HoursRequest() => create();

  HoursRequest._();

  factory HoursRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory HoursRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'HoursRequest',
      createEmptyInstance: create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  HoursRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  HoursRequest copyWith(void Function(HoursRequest) updates) =>
      super.copyWith((message) => updates(message as HoursRequest))
          as HoursRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static HoursRequest create() => HoursRequest._();
  @$core.override
  HoursRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static HoursRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<HoursRequest>(create);
  static HoursRequest? _defaultInstance;
}

class HoursResponse extends $pb.GeneratedMessage {
  factory HoursResponse({
    ComputeUnitThreshold? thresholds,
  }) {
    final result = create();
    if (thresholds != null) result.thresholds = thresholds;
    return result;
  }

  HoursResponse._();

  factory HoursResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory HoursResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'HoursResponse',
      createEmptyInstance: create)
    ..aOM<ComputeUnitThreshold>(1, _omitFieldNames ? '' : 'thresholds',
        subBuilder: ComputeUnitThreshold.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  HoursResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  HoursResponse copyWith(void Function(HoursResponse) updates) =>
      super.copyWith((message) => updates(message as HoursResponse))
          as HoursResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static HoursResponse create() => HoursResponse._();
  @$core.override
  HoursResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static HoursResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<HoursResponse>(create);
  static HoursResponse? _defaultInstance;

  @$pb.TagNumber(1)
  ComputeUnitThreshold get thresholds => $_getN(0);
  @$pb.TagNumber(1)
  set thresholds(ComputeUnitThreshold value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasThresholds() => $_has(0);
  @$pb.TagNumber(1)
  void clearThresholds() => $_clearField(1);
  @$pb.TagNumber(1)
  ComputeUnitThreshold ensureThresholds() => $_ensure(0);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
