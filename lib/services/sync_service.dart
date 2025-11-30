import 'dart:convert';
import '../models/task.dart';
import 'database_service.dart';
import 'task_api_service.dart';
import 'connectivity_service.dart';

class SyncService {
  static final SyncService instance = SyncService._init();
  SyncService._init();

  bool _isSyncing = false;

  Future<void> syncAll() async {
    if (!ConnectivityService.instance.isOnline) return;
    if (_isSyncing) return;

    _isSyncing = true;
    try {
      // 1) Processa FILA local primeiro
      final queue = await DatabaseService.instance.getSyncQueue();

      for (final item in queue) {
        final queueId = item['id'] as int;
        final action = item['action'] as String;
        final payload = jsonDecode(item['payload'] as String) as Map<String, dynamic>;
        final localTask = Task.fromMap(payload);

        try {
          if (action == 'CREATE') {
            // cria no servidor → servidor devolve versão definitiva (com updatedAt dele)
            final remote = await TaskApiService.instance.createTask(localTask);
            await DatabaseService.instance.update(remote);
          } else if (action == 'UPDATE') {
            final remote = await TaskApiService.instance.getTask(localTask.id!);

            if (remote == null) {
              // não existe no servidor → manda a local mesmo
              final updatedRemote = await TaskApiService.instance.updateTask(localTask);
              await DatabaseService.instance.update(updatedRemote);
            } else {
              // 🔥 LWW AQUI: quem tem updatedAt mais novo ganha
              if (localTask.updatedAt.isAfter(remote.updatedAt)) {
                // LOCAL venceu → sobe pro servidor
                final updatedRemote = await TaskApiService.instance.updateTask(localTask);
                await DatabaseService.instance.update(updatedRemote);
              } else if (remote.updatedAt.isAfter(localTask.updatedAt)) {
                // SERVIDOR venceu → sobrescreve local
                await DatabaseService.instance.update(remote);
              }
            }
          } else if (action == 'DELETE') {
            // aqui podemos considerar que o delete local "vence"
            await TaskApiService.instance.deleteTask(localTask.id!);
          }

          // se tudo deu certo, remove da fila
          await DatabaseService.instance.removeFromSyncQueue(queueId);
        } catch (e) {
          // se der erro em um item, não para toda a sync
          print('❌ Erro ao processar item da fila: $e');
        }
      }

      // 2) Reconciliar lista inteira (opcional, mas ajuda a garantir consistência)
      final remoteTasks = await TaskApiService.instance.getAllTasks();
      final localTasks = await DatabaseService.instance.readAll();

      final Map<int, Task> localById = {
        for (final t in localTasks.where((t) => t.id != null)) t.id!: t,
      };

      for (final remote in remoteTasks) {
        final local = localById[remote.id];

        if (local == null) {
          // existe no servidor mas não local → cria local
          await DatabaseService.instance.create(remote);
        } else {
          // 🔥 LWW de novo
          if (remote.updatedAt.isAfter(local.updatedAt)) {
            await DatabaseService.instance.update(remote);
          } else if (local.updatedAt.isAfter(remote.updatedAt)) {
            await TaskApiService.instance.updateTask(local);
          }
        }
      }
    } finally {
      _isSyncing = false;
    }
  }
}
