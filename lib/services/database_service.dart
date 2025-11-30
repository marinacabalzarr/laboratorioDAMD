import 'dart:async';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../models/task.dart';
import 'dart:convert';
import 'connectivity_service.dart';
import 'dart:async';
import 'dart:convert';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../models/task.dart';
import 'connectivity_service.dart';


class DatabaseService {
  static final DatabaseService instance = DatabaseService._init();
  static Database? _database;

  DatabaseService._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('tasks.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 7, // ✅ VERSÃO ATUALIZADA
      onCreate: _createDB,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
    CREATE TABLE tasks (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      title TEXT NOT NULL,
      description TEXT NOT NULL,
      priority TEXT NOT NULL,
      completed INTEGER NOT NULL,
      createdAt TEXT NOT NULL,
      updatedAt TEXT NOT NULL,   -- 🔹 NOVO
      photoPaths TEXT,
      completedAt TEXT,
      completedBy TEXT,
      latitude REAL,
      longitude REAL,
      locationName TEXT
    )
  ''');

    await db.execute('''
    CREATE TABLE sync_queue (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      action TEXT NOT NULL,       -- CREATE | UPDATE | DELETE
      entityId INTEGER,
      payload TEXT NOT NULL,      -- JSON da tarefa
      createdAt TEXT NOT NULL
    )
  ''');
  }



  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 5) {
      await db.execute('ALTER TABLE tasks ADD COLUMN photoPaths TEXT');
    }

    if (oldVersion < 6) {
      await db.execute('''
      CREATE TABLE sync_queue (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        action TEXT NOT NULL,
        entityId INTEGER,
        payload TEXT NOT NULL,
        createdAt TEXT NOT NULL
      )
    ''');
    }

    if (oldVersion < 7) {
      await db.execute('ALTER TABLE tasks ADD COLUMN updatedAt TEXT');

      // opcional: preencher updatedAt com createdAt para registros antigos
      await db.execute('UPDATE tasks SET updatedAt = createdAt WHERE updatedAt IS NULL');
    }
  }



  // ✅ CRIAR
  Future<Task> create(Task task) async {
    final db = await instance.database;
    final id = await db.insert('tasks', task.toMap());
    final createdTask = task.copyWith(id: id);

    // Se estiver OFFLINE, registra na fila
    if (!ConnectivityService.instance.isOnline) {
      await addToSyncQueue(
        action: 'CREATE',
        entityId: id,
        payload: jsonEncode(createdTask.toMap()),
      );
    }

    return createdTask;
  }


  // ✅ LER TODOS
  Future<List<Task>> readAll() async {
    final db = await instance.database;
    const orderBy = 'createdAt DESC';
    final result = await db.query('tasks', orderBy: orderBy);
    return result.map((json) => Task.fromMap(json)).toList();
  }

  // ✅ LER 1
  Future<Task?> read(int id) async {
    final db = await instance.database;
    final result = await db.query('tasks', where: 'id = ?', whereArgs: [id]);

    if (result.isNotEmpty) {
      return Task.fromMap(result.first);
    }
    return null;
  }

  // ✅ ATUALIZAR
  Future<int> update(Task task) async {
    final db = await instance.database;

    final result = await db.update(
      'tasks',
      task.toMap(),
      where: 'id = ?',
      whereArgs: [task.id],
    );

    if (!ConnectivityService.instance.isOnline) {
      await addToSyncQueue(
        action: 'UPDATE',
        entityId: task.id,
        payload: jsonEncode(task.toMap()),
      );
    }

    return result;
  }


  // ✅ DELETAR
  Future<int> delete(int id) async {
    final db = await instance.database;

    final task = await read(id);

    final result = await db.delete(
      'tasks',
      where: 'id = ?',
      whereArgs: [id],
    );

    if (!ConnectivityService.instance.isOnline && task != null) {
      await addToSyncQueue(
        action: 'DELETE',
        entityId: id,
        payload: jsonEncode(task.toMap()),
      );
    }

    return result;
  }


  // ✅ BUSCAR TAREFAS PRÓXIMAS POR LOCALIZAÇÃO
  Future<List<Task>> getTasksNearLocation({
    required double latitude,
    required double longitude,
    double radiusInMeters = 1000,
  }) async {
    final allTasks = await readAll();

    return allTasks.where((task) {
      if (!task.hasLocation) return false;

      // Distância aproximada (Haversine simplificada)
      final latDiff = (task.latitude! - latitude).abs();
      final lonDiff = (task.longitude! - longitude).abs();
      final distance = ((latDiff * 111000) + (lonDiff * 111000)) / 2;

      return distance <= radiusInMeters;
    }).toList();
  }

  // ✅ ADICIONAR AÇÃO NA FILA
  Future<void> addToSyncQueue({
    required String action, // CREATE | UPDATE | DELETE
    required int? entityId,
    required String payload,
  }) async {
    final db = await instancedatabase;

    await db.insert('sync_queue', {
      'action': action,
      'entityId': entityId,
      'payload': payload,
      'createdAt': DateTime.now().toIso8601String(),
    });

    print('📥 Ação "$action" adicionada na sync_queue');
  }

// ✅ BUSCAR TODA A FILA
  Future<List<Map<String, dynamic>>> getSyncQueue() async {
    final db = await instance.database;
    return await db.query('sync_queue', orderBy: 'createdAt ASC');
  }

// ✅ REMOVER ITEM DA FILA
  Future<void> removeFromSyncQueue(int id) async {
    final db = await instance.database;
    await db.delete('sync_queue', where: 'id = ?', whereArgs: [id]);
  }

  // ✅ FECHAR BANCO
  Future close() async {
    final db = await instance.database;
    db.close();
  }

}
