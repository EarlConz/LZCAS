import 'package:bot_toast/bot_toast.dart';
import 'package:flutter/material.dart';

/// Shows a success toast (green background + check icon).
void showSuccessToast(String text) {
  _showColoredToast(text, Colors.green.shade600, Icons.check_circle);
}

/// Shows an error toast (red background + error icon).
void showErrorToast(String text) {
  _showColoredToast(text, Colors.red.shade600, Icons.cancel);
}

void _showColoredToast(String text, Color color, IconData icon) {
  BotToast.showCustomText(
    align: const Alignment(1, -0.85),
    duration: const Duration(seconds: 4),
    toastBuilder: (cancel) => _ToastCard(text: text, color: color, icon: icon),
  );
}

class _ToastCard extends StatelessWidget {
  final String text;
  final Color color;
  final IconData icon;

  const _ToastCard({
    required this.text,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 6,
      color: color,
      margin: const EdgeInsets.only(top: 60, right: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 22),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                text,
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
