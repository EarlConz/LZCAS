import 'package:flutter/material.dart';

class DeleteMemberButton extends StatelessWidget {
  final Map<String, dynamic> member;
  final VoidCallback onDeleted;

  const DeleteMemberButton({
    super.key,
    required this.member,
    required this.onDeleted,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.delete, color: Colors.red),
      onPressed: () async {
        final confirm = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text("Confirm Delete"),
            content: Text("Do you want to delete ${member['firstName']}?"),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text("No"),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                ),
                onPressed: () => Navigator.pop(context, true),
                child: const Text("Yes"),
              ),
            ],
          ),
        );

        if (confirm == true) {
          onDeleted();
        }
      },
    );
  }
}