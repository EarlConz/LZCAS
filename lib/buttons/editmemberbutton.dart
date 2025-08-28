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
    String roleValue = member["role"] ?? "Member"; // ✅ dropdown value
    final contactController = TextEditingController(text: member["contactNo"] ?? ""); // ✅ allow null
    final birthdayController = TextEditingController(text: member["birthday"]);
    final addressController = TextEditingController(text: member["address"]);
    final pointsController = TextEditingController(text: member["points"].toString());
    final referrerController = TextEditingController(text: member["referrer"]);

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text("Edit Member"),
              content: SingleChildScrollView(
                child: Column(
                  children: [
                    TextField(controller: firstNameController, decoration: const InputDecoration(labelText: "First Name")),
                    TextField(controller: middleNameController, decoration: const InputDecoration(labelText: "Middle Name")),
                    TextField(controller: lastNameController, decoration: const InputDecoration(labelText: "Last Name")),
                    DropdownButtonFormField<String>(
                      value: roleValue,
                      decoration: const InputDecoration(labelText: "Role"),
                      items: const [
                        DropdownMenuItem(value: "Member", child: Text("Member")),
                        DropdownMenuItem(value: "Leader", child: Text("Leader")),
                      ],
                      onChanged: (value) {
                        setState(() {
                          roleValue = value!;
                        });
                      },
                    ),
                    TextField(
                      controller: contactController,
                      decoration: const InputDecoration(labelText: "Contact No."),
                      keyboardType: TextInputType.phone,
                    ),
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
                    // ✅ Contact No. validation (allow empty, but if filled -> must be numbers only)
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

                    final updatedMember = {
                      "firstName": firstNameController.text,
                      "middleName": middleNameController.text,
                      "lastName": lastNameController.text,
                      "role": roleValue, // ✅ use dropdown value
                      "contactNo": contactController.text.isEmpty
                          ? null
                          : contactController.text, // ✅ allow null
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
      },
    );
  }
}