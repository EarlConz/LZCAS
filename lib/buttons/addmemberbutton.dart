import 'package:flutter/material.dart';

class AddMemberButton extends StatelessWidget {
  final Function(Map<String, dynamic>) onMemberAdded;

  const AddMemberButton({
    super.key,
    required this.onMemberAdded,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.blue,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
      icon: const Icon(Icons.person_add, color: Colors.white),
      label: const Text(
        "Add Member",
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
      ),
      onPressed: () {
        // For now, we just add a placeholder member
        onMemberAdded({
          "lastName": "New",
          "firstName": "Member",
          "middleName": "X",
          "role": "Member",
          "contactNo": "09123456789",
          "birthday": "2000-01-01",
          "address": "New Street",
          "referrer": "N/A",
          "points": 0,
        });

        // Show confirmation
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("New member added!")),
        );
      },
    );
  }
}