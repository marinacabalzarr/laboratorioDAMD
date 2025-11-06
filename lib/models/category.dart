import 'package:flutter/material.dart';

class Category {
  final String id;
  final String name;
  final Color color;

  const Category({
    required this.id,
    required this.name,
    required this.color,
  });


  static final List<Category> predefined = [
    Category(id: 'work', name: 'Trabalho', color: Colors.blue),
    Category(id: 'personal', name: 'Pessoal', color: Colors.orange),
    Category(id: 'study', name: 'Estudos', color: Colors.green),
    Category(id: 'health', name: 'Saúde', color: Colors.pink),
    Category(id: 'home', name: 'Casa', color: Colors.purple),
  ];


  static Category? findById(String? id) {
    if (id == null) return null;
    try {
      return predefined.firstWhere((cat) => cat.id == id);
    } catch (_) {
      return null;
    }
  }

  /// 🔹 Para exibir nome e cor facilmente
  @override
  String toString() => 'Category($name)';
}
