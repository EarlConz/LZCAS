import 'package:flutter/material.dart';

class EditMemberButton extends StatelessWidget {
  final Map<String, dynamic> member;
  final ValueChanged<Map<String, dynamic>> onMemberUpdated;

  const EditMemberButton({
    super.key,
    required this.member,
    required this.onMemberUpdated,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.edit, color: Colors.blue),
      onPressed: () {
        _showEditDialog(context);
      },
    );
  }

  void _showEditDialog(BuildContext context) {
    final firstNameController = TextEditingController(text: member["firstName"]);
    final middleNameController = TextEditingController(text: member["middleName"]);
    final lastNameController = TextEditingController(text: member["lastName"]);
    final roleController = TextEditingController(text: member["role"]);
    final contactController = TextEditingController(text: member["contactNo"]); // ✅ fixed key
    final birthdayController = TextEditingController(text: member["birthday"]);
    final addressController = TextEditingController(text: member["address"]);
    final pointsController = TextEditingController(text: member["points"].toString());
    final referrerController = TextEditingController(text: member["referrer"]);

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Edit Member"),
          content: SingleChildScrollView(
            child: Column(
              children: [
                TextField(controller: firstNameController, decoration: const InputDecoration(labelText: "First Name")),
                TextField(controller: middleNameController, decoration: const InputDecoration(labelText: "Middle Name")),
                TextField(controller: lastNameController, decoration: const InputDecoration(labelText: "Last Name")),
                TextField(controller: roleController, decoration: const InputDecoration(labelText: "Role")),
                TextField(controller: contactController, decoration: const InputDecoration(labelText: "Contact No.")),
                TextField(controller: birthdayController, decoration: const InputDecoration(labelText: "Birthday")),
                TextField(controller: addressController, decoration: const InputDecoration(labelText: "Address")),
                TextField(
                  controller: pointsController,
                  decoration: const InputDecoration(labelText: "Points"),
                  keyboardType: TextInputType.number,
                ),
                TextField(controller: referrerController, decoration: const InputDecoration(labelText: "Referrer")),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
            ElevatedButton(
              onPressed: () {
                final updatedMember = {
                  "firstName": firstNameController.text,
                  "middleName": middleNameController.text,
                  "lastName": lastNameController.text,
                  "role": roleController.text,
                  "contactNo": contactController.text, // ✅ fixed key
                  "birthday": birthdayController.text,
                  "address": addressController.text,
                  "points": int.tryParse(pointsController.text) ?? 0,
                  "referrer": referrerController.text,
                };

                onMemberUpdated(updatedMember);
                Navigator.pop(context);

                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Member updated successfully!")),
                );
              },
              child: const Text("Save"),
            ),
          ],
        );
      },
    );
  }
}