import 'package:flutter/material.dart';
import 'package:lzcas/dialogs/birthday_picker_dialog.dart';
import 'package:lzcas/db/db.dart' show repository, Member;

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
  List<Member> _members = [];
  int? _selectedReferrerId;
  String _selectedReferrerName = '';

  Future<void> _pickBirthday() async {
    final birthday = await showBirthdayPickerDialog(
      context,
      initialValue: birthdayController.text,
    );
    if (birthday == null || !mounted) return;
    setState(() {
      birthdayController.text = birthday;
    });
  }

  @override
  void initState() {
    super.initState();
    _loadMembers();
  }

  Future<void> _loadMembers() async {
    final rows = await repository.fetchMembers();
    if (!mounted) return;
    setState(() {
      _members = rows;
    });
  }

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
              readOnly: true,
              onTap: _pickBirthday,
              decoration: const InputDecoration(
                labelText: "Birthday",
                suffixIcon: Icon(Icons.calendar_month_outlined),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: addressController,
              decoration: const InputDecoration(labelText: "Address"),
            ),
            const SizedBox(height: 16),
            // Referrer picker (None or an existing member)
            DropdownButtonFormField<int?>(
              initialValue: _selectedReferrerId,
              decoration: const InputDecoration(labelText: "Referrer (optional)"),
              items: [
                const DropdownMenuItem<int?>(value: null, child: Text('None')),
                ..._members.map((m) {
                  final label = '${m.firstName ?? ''} ${m.lastName ?? ''}'.trim();
                  return DropdownMenuItem<int?>(value: m.id, child: Text(label.isEmpty ? 'ID:${m.id}' : label));
                })
              ],
              onChanged: (v) {
                setState(() {
                  _selectedReferrerId = v;
                  final sel = _members.firstWhere((m) => m.id == v, orElse: () => Member(id: 0, lastName: null, firstName: null, middleName: null, role: null, contactNo: null, birthday: null, address: null, referrer: null, points: 0, qr: null));
                  _selectedReferrerName = sel.id == 0 ? '' : '${sel.firstName ?? ''} ${sel.lastName ?? ''}'.trim();
                });
              },
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

            final refText = _selectedReferrerName;
            final referrerId = _selectedReferrerId;

            final newMember = {
              "lastName": lastNameController.text,
              "firstName": firstNameController.text,
              "middleName": middleNameController.text,
              "contactNo": contactController.text.isEmpty
                  ? null
                  : contactController.text,
              "birthday": birthdayController.text,
              "address": addressController.text,
              "referrer": refText,
              "referrerId": referrerId,
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
