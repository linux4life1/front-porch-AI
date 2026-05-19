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

import 'package:protobuf/protobuf.dart' as $pb;

class DeviceType extends $pb.ProtobufEnum {
  static const DeviceType PHONE =
      DeviceType._(0, _omitEnumNames ? '' : 'PHONE');
  static const DeviceType TABLET =
      DeviceType._(1, _omitEnumNames ? '' : 'TABLET');
  static const DeviceType LAPTOP =
      DeviceType._(2, _omitEnumNames ? '' : 'LAPTOP');

  static const $core.List<DeviceType> values = <DeviceType>[
    PHONE,
    TABLET,
    LAPTOP,
  ];

  static final $core.List<DeviceType?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 2);
  static DeviceType? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const DeviceType._(super.value, super.name);
}

class ChunkState extends $pb.ProtobufEnum {
  static const ChunkState LAST_CHUNK =
      ChunkState._(0, _omitEnumNames ? '' : 'LAST_CHUNK');
  static const ChunkState MORE_CHUNKS =
      ChunkState._(1, _omitEnumNames ? '' : 'MORE_CHUNKS');

  static const $core.List<ChunkState> values = <ChunkState>[
    LAST_CHUNK,
    MORE_CHUNKS,
  ];

  static final $core.List<ChunkState?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 1);
  static ChunkState? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const ChunkState._(super.value, super.name);
}

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
