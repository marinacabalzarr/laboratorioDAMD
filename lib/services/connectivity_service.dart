import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';

class ConnectivityService {
  static final ConnectivityService instance = ConnectivityService._init();
  ConnectivityService._init();

  final _controller = StreamController<bool>.broadcast();

  Stream<bool> get isOnlineStream => _controller.stream;

  bool _isOnline = true;
  bool get isOnline => _isOnline;

  void initialize() async {
    // ✅ VERIFICA ESTADO INICIAL
    final result = await Connectivity().checkConnectivity();
    _updateStatus(result);

    // ✅ ESCUTA MUDANÇAS (VERSÃO 6+ TRABALHA COM LISTA)
    Connectivity().onConnectivityChanged.listen((results) {
      _updateStatus(results);
    });
  }

  void _updateStatus(List<ConnectivityResult> results) {
    final online = !results.contains(ConnectivityResult.none);

    if (online != _isOnline) {
      _isOnline = online;
      _controller.add(_isOnline);
      print(online ? '🟢 ONLINE' : '🔴 OFFLINE');
    }
  }

  void dispose() {
    _controller.close();
  }
}
