class Task {
  final int? id;
  final String title;
  final String description;
  final String priority;
  final bool completed;
  final DateTime createdAt;
  final DateTime updatedAt; // 🔹 NOVO

  // VÁRIAS FOTOS
  final List<String> photoPaths;

  // SENSORES
  final DateTime? completedAt;
  final String? completedBy;

  // GPS
  final double? latitude;
  final double? longitude;
  final String? locationName;

  Task({
    this.id,
    required this.title,
    required this.description,
    required this.priority,
    this.completed = false,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.photoPaths = const [],
    this.completedAt,
    this.completedBy,
    this.latitude,
    this.longitude,
    this.locationName,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now(); // 🔹 sempre tem valor

  bool get hasPhotos => photoPaths.isNotEmpty;
  bool get hasLocation => latitude != null && longitude != null;
  bool get wasCompletedByShake => completedBy == 'shake';

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'priority': priority,
      'completed': completed ? 1 : 0,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(), // 🔹 NOVO
      'photoPaths': photoPaths.join('|'),
      'completedAt': completedAt?.toIso8601String(),
      'completedBy': completedBy,
      'latitude': latitude,
      'longitude': longitude,
      'locationName': locationName,
    };
  }

  factory Task.fromMap(Map<String, dynamic> map) {
    final created = DateTime.parse(map['createdAt'] as String);

    // Pode ser que o banco antigo não tenha essa coluna ainda
    final updatedStr = map['updatedAt'] as String?;
    final updated = updatedStr != null ? DateTime.parse(updatedStr) : created;

    return Task(
      id: map['id'] as int?,
      title: map['title'] as String,
      description: map['description'] as String,
      priority: map['priority'] as String,
      completed: (map['completed'] as int) == 1,
      createdAt: created,
      updatedAt: updated,
      photoPaths: (map['photoPaths'] as String?)?.split('|') ?? [],
      completedAt: map['completedAt'] != null
          ? DateTime.parse(map['completedAt'] as String)
          : null,
      completedBy: map['completedBy'] as String?,
      latitude: map['latitude'] as double?,
      longitude: map['longitude'] as double?,
      locationName: map['locationName'] as String?,
    );
  }

  Task copyWith({
    int? id,
    String? title,
    String? description,
    String? priority,
    bool? completed,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<String>? photoPaths,
    DateTime? completedAt,
    String? completedBy,
    double? latitude,
    double? longitude,
    String? locationName,
  }) {
    return Task(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      priority: priority ?? this.priority,
      completed: completed ?? this.completed,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      photoPaths: photoPaths ?? this.photoPaths,
      completedAt: completedAt ?? this.completedAt,
      completedBy: completedBy ?? this.completedBy,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      locationName: locationName ?? this.locationName,
    );
  }
}
