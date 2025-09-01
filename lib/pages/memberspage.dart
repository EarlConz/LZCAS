import 'package:flutter/material.dart';
import '/widgets/memberstable.dart';
import '/widgets/memberdetails.dart';
import '/buttons/editmemberbutton.dart';
import '/buttons/deletememberbutton.dart';

class MembersPage extends StatefulWidget {
  const MembersPage({super.key});

  @override
  State<MembersPage> createState() => _MembersPageState();
}

class _MembersPageState extends State<MembersPage> {
  Map<String, dynamic>? selectedMember;

  final GlobalKey<MembersTableState> _tableKey = GlobalKey<MembersTableState>();

  void _updateMember(Map<String, dynamic> updatedMember) {
    if (selectedMember != null) {
      _tableKey.currentState?.updateMember(selectedMember!, updatedMember);

      setState(() {
        selectedMember = updatedMember;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Member updated successfully!")),
      );
    }
  }

  void _deleteMember() {
    if (selectedMember != null) {
      _tableKey.currentState?.removeMember(selectedMember!);

      setState(() {
        selectedMember = null;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Member deleted")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: MembersTable(
                key: _tableKey,
                onRowSelected: (member) {
                  setState(() {
                    selectedMember = member;
                  });
                },
              ),
            ),

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
