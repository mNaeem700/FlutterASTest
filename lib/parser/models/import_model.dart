import 'package:meta/meta.dart';

@immutable
class ImportModel {
  const ImportModel({
    required this.uri,
    required this.prefix,
    required this.isDeferred,
    required this.shownNames,
    required this.hiddenNames,
    required this.offset,
    required this.endOffset,
  });

  /// import 'package:flutter/material.dart';
  final String uri;

  /// import '...' as ui;
  final String? prefix;

  /// import '...' deferred as lib;
  final bool isDeferred;

  /// show A, B
  final List<String> shownNames;

  /// hide C, D
  final List<String> hiddenNames;

  /// Source start offset
  final int offset;

  /// Source end offset
  final int endOffset;
}
