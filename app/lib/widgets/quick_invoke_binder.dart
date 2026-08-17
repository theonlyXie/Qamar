import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../services/quick_invoke.dart';
import '../state/app_state.dart';

/// Wires iOS/Android shortcut launches into [AppState] for the life of the app.
class QuickInvokeBinder extends StatefulWidget {
  final Widget child;
  const QuickInvokeBinder({super.key, required this.child});

  @override
  State<QuickInvokeBinder> createState() => _QuickInvokeBinderState();
}

class _QuickInvokeBinderState extends State<QuickInvokeBinder> with WidgetsBindingObserver {
  StreamSubscription<QuickAction>? _sub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _drain());
    _sub = QuickInvoke.events().listen(_apply, onError: (_) {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _drain();
  }

  Future<void> _drain() async {
    final pending = await QuickInvoke.takePending();
    if (pending != null && mounted) _apply(pending);
  }

  void _apply(QuickAction action) {
    QuickInvoke.apply(context.read<AppState>(), action);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
