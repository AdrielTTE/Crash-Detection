import 'package:flutter/material.dart';

/// Whether the "what is this for" copy is currently shown.
///
/// Carried by an InheritedWidget rather than threaded through every
/// constructor: the flag is read at the leaves ([ValueRow]) but toggled at the
/// root, and passing a bool through five widget layers to reach them adds a
/// parameter to each without adding meaning to any.
class ExplainScope extends InheritedWidget {
  const ExplainScope({
    super.key,
    required this.explain,
    required super.child,
  });

  final bool explain;

  static bool of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<ExplainScope>();
    return scope?.explain ?? false;
  }

  @override
  bool updateShouldNotify(ExplainScope oldWidget) =>
      oldWidget.explain != explain;
}
