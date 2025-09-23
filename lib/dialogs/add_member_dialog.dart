import 'package:flutter/material.dart';

class AddMemberDialog extends StatefulWidget {
  final Function(Map<String, dynamic>) onMemberAdded;

  const AddMemberDialog({super.key, required this.onMemberAdded});

  @override
  State<AddMemberDialog> createState() => _AddMemberDialogState();
}

class _AddMemberDialogState extends State<AddMemberDialog> {
  final lastNameController = TextEditingController();
  final firstNameController = TextEditingController();
  final middleNameController = TextEditingController();
  final contactController = TextEditingController();
  final birthdayController = TextEditingController();
  final addressController = TextEditingController();
  final referrerController = TextEditingController();

  @override
  void dispose() {
    lastNameController.dispose();
    firstNameController.dispose();
    middleNameController.dispose();
    contactController.dispose();
    birthdayController.dispose();
    addressController.dispose();
    referrerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Add New Member"),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: lastNameController,
              decoration: const InputDecoration(labelText: "Last Name"),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: firstNameController,
              decoration: const InputDecoration(labelText: "First Name"),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: middleNameController,
              decoration: const InputDecoration(labelText: "Middle Name"),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: contactController,
              decoration: const InputDecoration(labelText: "Contact No."),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: birthdayController,
              decoration: const InputDecoration(labelText: "Birthday"),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: addressController,
              decoration: const InputDecoration(labelText: "Address"),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: referrerController,
              decoration: const InputDecoration(labelText: "Referrer"),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("Cancel"),
        ),
        ElevatedButton(
          onPressed: () {
            // ✅ Validation check for name
            if (lastNameController.text.trim().isEmpty ||
                firstNameController.text.trim().isEmpty ||
                middleNameController.text.trim().isEmpty) {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text("Error"),
                  content: const Text("Must put full name"),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text("OK"),
                    ),
                  ],
                ),
              );
              return;
            }

            // ✅ Contact No. check: allow empty, but validate numbers if not empty
            if (contactController.text.trim().isNotEmpty &&
                !RegExp(r'^[0-9]+$').hasMatch(contactController.text)) {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text("Error"),
                  content: const Text("Contact No. must be numbers only"),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text("OK"),
                    ),
                  ],
                ),
              );
              return;
            }

            final newMember = {
              "lastName": lastNameController.text,
              "firstName": firstNameController.text,
              "middleName": middleNameController.text,
              "contactNo": contactController.text.isEmpty
                  ? null
                  : contactController.text,
              "birthday": birthdayController.text,
              "address": addressController.text,
              "referrer": referrerController.text,
              "points": 0, // default
              "role": "Member", // default
            };

            widget.onMemberAdded(newMember);
            Navigator.pop(context);

            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Member added successfully!")),
              );
            }
          },
          child: const Text("Confirm"),
        ),
      ],
    );
  }
}
