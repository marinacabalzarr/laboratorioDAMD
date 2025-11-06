import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import '../screens/camera_screen.dart';

class CameraService {
  static final CameraService instance = CameraService._init();
  CameraService._init();

  List<CameraDescription>? _cameras;

  Future<void> initialize() async {
    try {
      _cameras = await availableCameras();
    } catch (_) {
      _cameras = [];
    }
  }

  Future<String?> takePicture(BuildContext context) async {
    if (_cameras == null || _cameras!.isEmpty) return null;

    final controller = CameraController(_cameras!.first, ResolutionPreset.high, enableAudio: false);
    await controller.initialize();

    final imagePath = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => CameraScreen(controller: controller),
      ),
    );

    controller.dispose();
    return imagePath;
  }

  Future<List<String>?> pickMultipleFromGallery() async {
    final picker = ImagePicker();
    final images = await picker.pickMultiImage();
    if (images.isEmpty) return null;

    List<String> paths = [];
    for (var img in images) {
      paths.add(await savePicture(XFile(img.path)));
    }
    return paths;
  }

  Future<String> savePicture(XFile image) async {
    final appDir = await getApplicationDocumentsDirectory();
    final fileName = 'task_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final savePath = path.join(appDir.path, 'images', fileName);

    await Directory(path.join(appDir.path, 'images')).create(recursive: true);
    return (await File(image.path).copy(savePath)).path;
  }

  Future<void> deletePhotos(List<String> paths) async {
    try {
      for (final path in paths) {
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
        }
      }
      print('🗑️ Todas as fotos foram removidas.');
    } catch (e) {
      print('❌ Erro ao deletar fotos: $e');
    }
  }

}
