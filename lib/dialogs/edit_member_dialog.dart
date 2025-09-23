import 'package:flutter/material.dart';

class EditMemberDialog extends StatefulWidget {
  final Map<String, dynamic> member;
  final ValueChanged<Map<String, dynamic>> onMemberUpdated;

  const EditMemberDialog({
    super.key,
    required this.member,
    required this.onMemberUpdated,
  });

  @override
  State<EditMemberDialog> createState() => _EditMemberDialogState();
}

class _EditMemberDialogState extends State<EditMemberDialog> {
  late final TextEditingController firstNameController;
  late final TextEditingController middleNameController;
  late final TextEditingController lastNameController;
  late String roleValue;
  late final TextEditingController contactController;
  late final TextEditingController birthdayController;
  late final TextEditingController addressController;
  late final TextEditingController pointsController;
  late final TextEditingController referrerController;

  @override
  void initState() {
    super.initState();
    firstNameController = TextEditingController(
      text: widget.member["firstName"],
    );
    middleNameController = TextEditingController(
      text: widget.member["middleName"],
    );
    lastNameController = TextEditingController(text: widget.member["lastName"]);
    roleValue = widget.member["role"] ?? "Member";
    contactController = TextEditingController(
      text: widget.member["contactNo"] ?? "",
    );
    birthdayController = TextEditingController(text: widget.member["birthday"]);
    addressController = TextEditingController(text: widget.member["address"]);
    pointsController = TextEditingController(
      text: widget.member["points"].toString(),
    );
    referrerController = TextEditingController(text: widget.member["referrer"]);
  }

  @override
  void dispose() {
    firstNameController.dispose();
    middleNameController.dispose();
    lastNameController.dispose();
    contactController.dispose();
    birthdayController.dispose();
    addressController.dispose();
    pointsController.dispose();
    referrerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Edit Member"),
      content: SingleChildScrollView(
        child: Column(
          children: [
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
              controller: lastNameController,
              decoration: const InputDecoration(labelText: "Last Name"),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: roleValue,
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
              controller: pointsController,
              decoration: const InputDecoration(labelText: "Points"),
              keyboardType: TextInputType.number,
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
              "role": roleValue,
              "contactNo": contactController.text.isEmpty
                  ? null
                  : contactController.text,
              "birthday": birthdayController.text,
              "address": addressController.text,
              "points": int.tryParse(pointsController.text) ?? 0,
              "referrer": referrerController.text,
            };

            widget.onMemberUpdated(updatedMember);
            Navigator.pop(context);

            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Member updated successfully!")),
            );
          },
          child: const Text("Save"),
        ),
      ],
    );
  }
}
