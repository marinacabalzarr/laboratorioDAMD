import 'package:flutter/material.dart';
import '../services/connectivity_service.dart';

class ConnectivityBanner extends StatelessWidget {
  const ConnectivityBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
      stream: ConnectivityService.instance.isOnlineStream,
      initialData: ConnectivityService.instance.isOnline,
      builder: (context, snapshot) {
        final isOnline = snapshot.data ?? true;

        return AnimatedContainer(
          duration: const Duration(milliseconds: 400),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 6),
          color: isOnline ? Colors.green : Colors.red.shade700,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isOnline ? Icons.wifi : Icons.wifi_off,
                color: Colors.white,
                size: 16,
              ),
              const SizedBox(width: 8),
              Text(
                isOnline ? 'Modo Online' : 'Modo Offline',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
