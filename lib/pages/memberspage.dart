import 'package:flutter/material.dart';
import '/widgets/memberstable.dart';
import '/widgets/searchmembers.dart';
import '/widgets/memberdetails.dart';
import '/buttons/editmemberbutton.dart';
import '/buttons/deletememberbutton.dart';
import '/buttons/addmemberbutton.dart';

class MembersPage extends StatefulWidget {
  const MembersPage({super.key});

  @override
  State<MembersPage> createState() => _MembersPageState();
}

class _MembersPageState extends State<MembersPage> {
  String searchTerm = "";
  Map<String, dynamic>? selectedMember;

  final GlobalKey<MembersTableState> _tableKey = GlobalKey<MembersTableState>();

  void _updateMember(Map<String, dynamic> updatedMember) {
    setState(() {
      selectedMember = updatedMember;
    });
  }

  void _deleteMember() {
    setState(() {
      selectedMember = null;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Member deleted")),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 🔎 Search bar + Add button in one row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
              child: Row(
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
                  const SizedBox(width: 8),
                  AddMemberButton(
                    onMemberAdded: (newMember) {
                      _tableKey.currentState?.addMember(newMember);
                    },
                  ),
                ],
              ),
            ),

            // 📋 Members Table fills the whole screen
            Expanded(
              child: MembersTable(
                key: _tableKey,
                searchTerm: searchTerm,
                onRowSelected: (member) {
                  setState(() {
                    selectedMember = member;
                  });
                },
              ),
            ),

            // 📇 Details at bottom (optional)
            if (selectedMember != null)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.all(8),
                child: Stack(
                  children: [
                    MemberDetailsCard(member: selectedMember!),
                    Positioned(
                      top: 8,
                      right: 56,
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
              ),
          ],
        ),
      ),
    );
  }
}