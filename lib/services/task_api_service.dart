import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/task.dart';

class TaskApiService {
  static final TaskApiService instance = TaskApiService._init();
  TaskApiService._init();

  // TODO: ajustar pro endereço real da sua API
  final String baseUrl = 'http://10.0.2.2:3000'; // emulador Android apontando pro localhost

  Future<List<Task>> getAllTasks() async {
    final response = await http.get(Uri.parse('$baseUrl/tasks'));

    if (response.statusCode == 200) {
      final List data = jsonDecode(response.body);
      return data.map((e) => Task.fromMap(e as Map<String, dynamic>)).toList();
    } else {
      throw Exception('Erro ao buscar tasks (${response.statusCode})');
    }
  }

  Future<Task?> getTask(int id) async {
    final response = await http.get(Uri.parse('$baseUrl/tasks/$id'));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return Task.fromMap(data);
    } else if (response.statusCode == 404) {
      return null;
    } else {
      throw Exception('Erro ao buscar task (${response.statusCode})');
    }
  }

  Future<Task> createTask(Task task) async {
    final response = await http.post(
      Uri.parse('$baseUrl/tasks'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(task.toMap()),
    );

    if (response.statusCode == 201 || response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return Task.fromMap(data);
    } else {
      throw Exception('Erro ao criar task (${response.statusCode})');
    }
  }

  Future<Task> updateTask(Task task) async {
    final response = await http.put(
      Uri.parse('$baseUrl/tasks/${task.id}'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(task.toMap()),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return Task.fromMap(data);
    } else {
      throw Exception('Erro ao atualizar task (${response.statusCode})');
    }
  }

  Future<void> deleteTask(int id) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/tasks/$id'),
    );

    if (response.statusCode != 200 && response.statusCode != 204 && response.statusCode != 404) {
      throw Exception('Erro ao deletar task (${response.statusCode})');
    }
  }
}
