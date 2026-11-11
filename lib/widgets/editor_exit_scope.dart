import 'package:flutter/widgets.dart';

/// Lets an enclosing workspace ask its active editor before leaving/signing out.
/// No draft data is retained here. Forced authentication changes still dispose
/// the private workspace immediately.
class EditorExitCoordinator {
  Object? _owner;
  Future<bool> Function()? _request;

  void register(Object owner, Future<bool> Function() request) {
    _owner = owner;
    _request = request;
  }

  void unregister(Object owner) {
    if (!identical(owner, _owner)) return;
    _owner = null;
    _request = null;
  }

  Future<bool> requestExit() async => await _request?.call() ?? true;
}

class EditorExitScope extends InheritedWidget {
  const EditorExitScope({
    super.key,
    required this.coordinator,
    required super.child,
  });
  final EditorExitCoordinator coordinator;

  static EditorExitCoordinator? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<EditorExitScope>()
      ?.coordinator;

  @override
  bool updateShouldNotify(EditorExitScope oldWidget) =>
      coordinator != oldWidget.coordinator;
}
