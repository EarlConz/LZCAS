import 'package:flutter/material.dart';
import '/widgets/memberstable.dart';
import '/widgets/searchmembers.dart';
import '/widgets/memberdetails.dart';
import '/buttons/editmemberbutton.dart'; // ✅ Import the edit button
import '/buttons/deletememberbutton.dart'; // ✅ Import the delete button
import '/buttons/addmemberbutton.dart'; // ✅ Import the add button

class MembersPage extends StatefulWidget {
  const MembersPage({super.key});

  @override
  State<MembersPage> createState() => _MembersPageState();
}

class _MembersPageState extends State<MembersPage> {
  String searchTerm = "";
  Map<String, dynamic>? selectedMember;

  void _updateMember(Map<String, dynamic> updatedMember) {
    setState(() {
      selectedMember = updatedMember; // update details card
    });
  }

  void _deleteMember() {
    setState(() {
      selectedMember = null; // hide details card after delete
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Member deleted")),
    );
  }

  void _addMember(Map<String, dynamic> newMember) {
    setState(() {
      selectedMember = newMember; // show new member details immediately
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("New member added!")),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 🔎 Search bar + ➕ Add Member button
            Row(
              children: [
                Expanded(
                  child: SearchMembersWidget(
                    onChanged: (value) {
                      setState(() {
                        searchTerm = value;
                      });
                    },
                  ),
                ),
                const SizedBox(width: 10),
                AddMemberButton(
                  onMemberAdded: _addMember,
                ),
              ],
            ),
            const SizedBox(height: 10),

            // 📋 Members Table with responsive height
            SizedBox(
              height: screenHeight * 0.5, // table takes ~50% of screen
              child: MembersTable(
                searchTerm: searchTerm,
                onRowSelected: (member) {
                  setState(() {
                    selectedMember = member;
                  });
                },
              ),
            ),

            const SizedBox(height: 20),

            // 📇 Member Details Card + Edit + Delete buttons
            if (selectedMember != null)
              Stack(
                children: [
                  MemberDetailsCard(member: selectedMember!),
                  Positioned(
                    top: 8,
                    right: 56, // ✅ leave space for delete button
                    child: EditMemberButton(
                      member: selectedMember!,
                      onMemberUpdated: _updateMember,
                    ),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: DeleteMemberButton(
                      member: selectedMember!,
                      onDeleted: _deleteMember,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
