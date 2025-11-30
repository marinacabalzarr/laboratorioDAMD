import 'dart:io';
import 'package:flutter/material.dart';
import '../models/task.dart';
import '../services/connectivity_service.dart';

class TaskCard extends StatelessWidget {
  final Task task;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final Function(bool?) onCheckboxChanged;

  const TaskCard({
    super.key,
    required this.task,
    required this.onTap,
    required this.onDelete,
    required this.onCheckboxChanged,
  });

  Color _getPriorityColor() {
    switch (task.priority) {
      case 'urgent':
        return Colors.red;
      case 'high':
        return Colors.orange;
      case 'medium':
        return Colors.amber;
      case 'low':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  IconData _getPriorityIcon() {
    switch (task.priority) {
      case 'urgent':
        return Icons.priority_high;
      case 'high':
        return Icons.arrow_upward;
      case 'medium':
        return Icons.remove;
      case 'low':
        return Icons.arrow_downward;
      default:
        return Icons.flag;
    }
  }

  String _getPriorityLabel() {
    switch (task.priority) {
      case 'urgent':
        return 'Urgente';
      case 'high':
        return 'Alta';
      case 'medium':
        return 'Média';
      case 'low':
        return 'Baixa';
      default:
        return 'Normal';
    }
  }

  @override
  Widget build(BuildContext context) {
    final priorityColor = _getPriorityColor();

    // ✅ se estiver offline, mostra "Pendente"; se online, "Sincronizado"
    final bool isOffline = !ConnectivityService.instance.isOnline;

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: task.completed
              ? Colors.grey.shade300
              : priorityColor.withOpacity(0.3),
          width: 2,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // CABEÇALHO
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Checkbox(
                    value: task.completed,
                    onChanged: onCheckboxChanged,
                    activeColor: Colors.green,
                  ),

                  const SizedBox(width: 8),

                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // TÍTULO
                        Text(
                          task.title,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            decoration: task.completed
                                ? TextDecoration.lineThrough
                                : null,
                            color: task.completed
                                ? Colors.grey
                                : Colors.black87,
                          ),
                        ),

                        // DESCRIÇÃO
                        if (task.description.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            task.description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              color: task.completed
                                  ? Colors.grey
                                  : Colors.black54,
                            ),
                          ),
                        ],

                        const SizedBox(height: 8),

                        // TAGS
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            // PRIORIDADE
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: priorityColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: priorityColor.withOpacity(0.5),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    _getPriorityIcon(),
                                    color: priorityColor,
                                    size: 14,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    _getPriorityLabel(),
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      color: priorityColor,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // FOTOS
                            if (task.hasPhotos)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.blue.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Colors.blue.withOpacity(0.5),
                                  ),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.photo,
                                        size: 14, color: Colors.blue),
                                    SizedBox(width: 4),
                                    Text(
                                      'Fotos',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                        color: Colors.blue,
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                            // SHAKE TAG
                            if (task.completed && task.wasCompletedByShake)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.green.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Colors.green.withOpacity(0.5),
                                  ),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.vibration,
                                        size: 14, color: Colors.green),
                                    SizedBox(width: 4),
                                    Text(
                                      "Shake",
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.green,
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                            // ✅ STATUS DE SINCRONIZAÇÃO (PENDENTE / SINCRONIZADO)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: isOffline
                                    ? Colors.orange.withOpacity(0.1)
                                    : Colors.green.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isOffline
                                      ? Colors.orange.withOpacity(0.5)
                                      : Colors.green.withOpacity(0.5),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    isOffline
                                        ? Icons.cloud_off
                                        : Icons.check_circle,
                                    size: 14,
                                    color: isOffline
                                        ? Colors.orange
                                        : Colors.green,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    isOffline
                                        ? 'Pendente'
                                        : 'Sincronizado',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      color: isOffline
                                          ? Colors.orange
                                          : Colors.green,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // DELETAR
                  IconButton(
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline),
                    color: Colors.red,
                  ),
                ],
              ),
            ),

            // ✅ MINI GALERIA DE FOTOS (COM TRATAMENTO DE ERRO)
            if (task.hasPhotos)
              SizedBox(
                height: 90,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding:
                  const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  children: task.photoPaths.map((path) {
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(
                          File(path),
                          width: 90,
                          height: 90,
                          fit: BoxFit.cover,
                          errorBuilder:
                              (context, error, stackTrace) {
                            return Container(
                              width: 90,
                              height: 90,
                              color: Colors.grey.shade300,
                              child: const Icon(
                                Icons.broken_image,
                                color: Colors.grey,
                              ),
                            );
                          },
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
