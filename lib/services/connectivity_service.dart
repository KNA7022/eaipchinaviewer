import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class ConnectivityService {
  final _connectivity = Connectivity();
  final _controller = StreamController<bool>.broadcast();
  StreamSubscription<ConnectivityResult>? _subscription;

  Stream<bool> get onConnectivityChanged => _controller.stream;
  bool _isOnline = true;
  bool get isOnline => _isOnline;

  ConnectivityService() {
    _subscription = _connectivity.onConnectivityChanged.listen(_updateState);
    checkConnectivity();
  }

  Future<void> checkConnectivity() async {
    final result = await _connectivity.checkConnectivity();
    _updateState(result);
  }

  void _updateState(ConnectivityResult result) {
    _isOnline = result != ConnectivityResult.none;
    _controller.add(_isOnline);
  }

  void dispose() {
    _subscription?.cancel();
    _controller.close();
  }
}
