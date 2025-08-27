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
        showDialog(
          context: context,
          builder: (context) {
            // Controllers for input fields
            final lastNameController = TextEditingController();
            final firstNameController = TextEditingController();
            final middleNameController = TextEditingController();
            final contactController = TextEditingController();
            final birthdayController = TextEditingController();
            final addressController = TextEditingController();
            final referrerController = TextEditingController();

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
                    // ✅ Validation check
                    if (lastNameController.text.trim().isEmpty ||
                        firstNameController.text.trim().isEmpty ||
                        middleNameController.text.trim().isEmpty) {
                      // show popup
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
                      return; // stop execution
                    }

                    final newMember = {
                      "lastName": lastNameController.text,
                      "firstName": firstNameController.text,
                      "middleName": middleNameController.text,
                      "contactNo": contactController.text,
                      "birthday": birthdayController.text,
                      "address": addressController.text,
                      "referrer": referrerController.text,
                      "points": 15, // default
                      "role": "Member", // default
                    };

                    onMemberAdded(newMember);
                    Navigator.pop(context);

                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Member added successfully!")),
                    );
                  },
                  child: const Text("Confirm"),
                ),
              ],
            );
          },
        );
      },
    );
  }
}