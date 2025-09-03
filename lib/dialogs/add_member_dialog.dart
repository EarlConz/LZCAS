import 'package:flutter/material.dart';
import '/widgets/qrgenerator.dart';

class AddMemberDialog extends StatefulWidget {
  final Function(Map<String, dynamic>) onMemberAdded;

  const AddMemberDialog({
    super.key,
    required this.onMemberAdded,
  });

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
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
      ),
      title: const Text("Add New Member"),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: lastNameController,
              decoration: const InputDecoration(labelText: "Last Name"),
            ),
            TextField(
              controller: firstNameController,
              decoration: const InputDecoration(labelText: "First Name"),
            ),
            TextField(
              controller: middleNameController,
              decoration: const InputDecoration(labelText: "Middle Name"),
            ),
            TextField(
              controller: contactController,
              decoration: const InputDecoration(labelText: "Contact No."),
              keyboardType: TextInputType.phone,
            ),
            TextField(
              controller: birthdayController,
              decoration: const InputDecoration(labelText: "Birthday"),
            ),
            TextField(
              controller: addressController,
              decoration: const InputDecoration(labelText: "Address"),
            ),
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
            
            final qrdata = "${lastNameController.text}, ${firstNameController.text} ${middleNameController.text}";
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
              "qr": qrdata,
            };

            widget.onMemberAdded(newMember);
            Navigator.pop(context);

            // ✅ Show QR Code popup after adding member
            showDialog(
              context: context,
              builder: (context) => Dialog(
                backgroundColor: Colors.transparent,
                insetPadding: const EdgeInsets.all(20),
                child: QrGenerator(
                  lastName: lastNameController.text,
                  firstName: firstNameController.text,
                  middleName: middleNameController.text,
                ),
              ),
            );

            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Member added successfully!")),
            );
          },
          child: const Text("Confirm"),
        ),
      ],
    );
  }
}
