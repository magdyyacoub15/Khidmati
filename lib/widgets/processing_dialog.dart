import 'package:flutter/material.dart';

class ProcessingDialog extends StatelessWidget {
  final String status;
  final double? progress; // 0.0 to 1.0

  const ProcessingDialog({super.key, required this.status, this.progress});

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, // Prevent dismissing
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 20),
            Text(
              status,
              style: const TextStyle(fontSize: 16),
              textAlign: TextAlign.center,
            ),
            if (progress != null) ...[
              const SizedBox(height: 10),
              LinearProgressIndicator(value: progress),
              const SizedBox(height: 5),
              Text(
                "${(progress! * 100).toStringAsFixed(0)}%",
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
