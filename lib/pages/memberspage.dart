import 'package:flutter/material.dart';
import '/widgets/memberstable.dart';
import '/widgets/searchmembers.dart';
import '/widgets/memberdetails.dart';
import '/buttons/editmemberbutton.dart'; // ✅ Import the edit button

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

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 🔎 Search bar
            SearchMembersWidget(
              onChanged: (value) {
                setState(() {
                  searchTerm = value;
                });
              },
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

            // 📇 Member Details Card + Edit button
            if (selectedMember != null)
              Stack(
                children: [
                  MemberDetailsCard(member: selectedMember!),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: EditMemberButton(
                      member: selectedMember!,
                      onMemberUpdated: _updateMember,
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