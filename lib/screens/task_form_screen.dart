import 'dart:io';
import 'package:flutter/material.dart';
import '../models/task.dart';
import '../services/camera_service.dart';
import '../services/database_service.dart';
import '../services/location_service.dart';
import '../widgets/location_picker.dart';

class TaskFormScreen extends StatefulWidget {
  final Task? task;

  const TaskFormScreen({super.key, this.task});

  @override
  State<TaskFormScreen> createState() => _TaskFormScreenState();
}

class _TaskFormScreenState extends State<TaskFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();

  String _priority = 'medium';
  bool _completed = false;
  bool _isLoading = false;

  // LISTA DE FOTOS
  List<String> _photoPaths = [];

  // GPS
  double? _latitude;
  double? _longitude;
  String? _locationName;

  @override
  void initState() {
    super.initState();

    if (widget.task != null) {
      _titleController.text = widget.task!.title;
      _descriptionController.text = widget.task!.description;
      _priority = widget.task!.priority;
      _completed = widget.task!.completed;
      _photoPaths = [...widget.task!.photoPaths];
      _latitude = widget.task!.latitude;
      _longitude = widget.task!.longitude;
      _locationName = widget.task!.locationName;
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  // CAMERA
  Future<void> _takePicture() async {
    final photoPath = await CameraService.instance.takePicture(context);
    if (photoPath != null && mounted) {
      setState(() => _photoPaths.add(photoPath));
    }
  }

  // GALERIA (VÁRIAS)
  Future<void> _pickMultipleFromGallery() async {
    final selected = await CameraService.instance.pickMultipleFromGallery();
    if (selected != null && mounted) {
      setState(() => _photoPaths.addAll(selected));
    }
  }

  // REMOVER FOTO INDIVIDUAL
  void _removePhotoAt(int index) {
    setState(() => _photoPaths.removeAt(index));
  }

  // VISUALIZAR FOTO
  void _viewPhoto(String path) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0),
          body: Center(
            child: InteractiveViewer(
              child: Image.file(File(path), fit: BoxFit.contain),
            ),
          ),
        ),
      ),
    );
  }

  // LOCALIZAÇÃO
  void _showLocationPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => LocationPicker(
        initialLatitude: _latitude,
        initialLongitude: _longitude,
        initialAddress: _locationName,
        onLocationSelected: (lat, lon, address) {
          setState(() {
            _latitude = lat;
            _longitude = lon;
            _locationName = address;
          });
          Navigator.pop(context);
        },
      ),
    );
  }

  void _removeLocation() {
    setState(() {
      _latitude = null;
      _longitude = null;
      _locationName = null;
    });
  }

  // SALVAR
  Future<void> _saveTask() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final task = Task(
        id: widget.task?.id,
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        priority: _priority,
        completed: _completed,
        photoPaths: _photoPaths,
        latitude: _latitude,
        longitude: _longitude,
        locationName: _locationName,
      );

      if (widget.task == null) {
        await DatabaseService.instance.create(task);
      } else {
        await DatabaseService.instance.update(task);
      }

      Navigator.pop(context, true);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.task != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Editar Tarefa' : 'Nova Tarefa'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [

              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: 'Título *',
                  prefixIcon: Icon(Icons.title),
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                v == null || v.trim().isEmpty ? 'Digite um título' : null,
              ),

              const SizedBox(height: 16),

              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Descrição',
                  prefixIcon: Icon(Icons.description),
                  border: OutlineInputBorder(),
                ),
                maxLines: 4,
              ),

              const SizedBox(height: 16),

              DropdownButtonFormField<String>(
                value: _priority,
                decoration: const InputDecoration(
                  labelText: 'Prioridade',
                  prefixIcon: Icon(Icons.flag),
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'low', child: Text('🟢 Baixa')),
                  DropdownMenuItem(value: 'medium', child: Text('🟡 Média')),
                  DropdownMenuItem(value: 'high', child: Text('🟠 Alta')),
                  DropdownMenuItem(value: 'urgent', child: Text('🔴 Urgente')),
                ],
                onChanged: (value) => setState(() => _priority = value!),
              ),

              const SizedBox(height: 24),

              // FOTOS - MULTI
              Row(
                children: [
                  const Icon(Icons.photo, color: Colors.blue),
                  const SizedBox(width: 8),
                  const Text('Fotos', style: TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),

              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _takePicture,
                      icon: const Icon(Icons.camera_alt),
                      label: const Text('Câmera'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickMultipleFromGallery,
                      icon: const Icon(Icons.photo_library),
                      label: const Text('Galeria'),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              if (_photoPaths.isNotEmpty)
                SizedBox(
                  height: 120,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _photoPaths.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (_, i) => Stack(
                      children: [
                        GestureDetector(
                          onTap: () => _viewPhoto(_photoPaths[i]),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.file(
                              File(_photoPaths[i]),
                              width: 120,
                              height: 120,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                        Positioned(
                          top: 4,
                          right: 4,
                          child: GestureDetector(
                            onTap: () => _removePhotoAt(i),
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.black54,
                              ),
                              child: const Icon(Icons.close, size: 18, color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              const Divider(height: 32),

              // LOCALIZAÇÃO
              Row(
                children: [
                  const Icon(Icons.location_on, color: Colors.blue),
                  const SizedBox(width: 8),
                  const Text('Localização', style: TextStyle(fontWeight: FontWeight.bold)),
                  const Spacer(),
                  if (_latitude != null)
                    TextButton(
                      onPressed: _removeLocation,
                      child: const Text('Remover', style: TextStyle(color: Colors.red)),
                    ),
                ],
              ),

              const SizedBox(height: 12),

              if (_latitude != null && _longitude != null)
                Card(
                  child: ListTile(
                    title: Text(_locationName ?? 'Localização definida'),
                    subtitle: Text(
                      LocationService.instance.formatCoordinates(_latitude!, _longitude!),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.edit),
                      onPressed: _showLocationPicker,
                    ),
                  ),
                )
              else
                OutlinedButton.icon(
                  onPressed: _showLocationPicker,
                  icon: const Icon(Icons.add_location),
                  label: const Text('Adicionar Localização'),
                ),

              const SizedBox(height: 32),

              ElevatedButton.icon(
                onPressed: _isLoading ? null : _saveTask,
                icon: const Icon(Icons.save),
                label: Text(isEditing ? 'Atualizar' : 'Criar Tarefa'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.all(16),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
