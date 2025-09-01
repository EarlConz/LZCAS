import 'package:flutter/material.dart';
import '/widgets/search.dart';
import '/widgets/custom_elevated_button.dart';
import '/dialogs/add_member_dialog.dart';

class MembersTable extends StatefulWidget {
  final Function(Map<String, dynamic>) onRowSelected;

  const MembersTable({
    super.key,
    required this.onRowSelected,
  });

  @override
  MembersTableState createState() => MembersTableState();
}

class MembersTableState extends State<MembersTable> {
  String searchTerm = "";
  final List<Map<String, dynamic>> members = [
    {
      "lastName": "Cruz",
      "firstName": "Juan",
      "middleName": "Dela",
      "role": "Leader",
      "contactNo": "09171234567",
      "birthday": "Jan 10, 1990",
      "address": "Quezon City",
      "referrer": "Reyes",
      "points": 15,
    },
    {
      "lastName": "Reyes",
      "firstName": "Maria",
      "middleName": "Lopez",
      "role": "Member",
      "contactNo": "09182345678",
      "birthday": "Feb 20, 1992",
      "address": "Makati City",
      "referrer": "Cruz",
      "points": 15,
    },
  ];

  void addMember(Map<String, dynamic> newMember) {
    setState(() {
      members.add(newMember);
    });
  }

  void updateMember(Map<String, dynamic> oldMember, Map<String, dynamic> updatedMember) {
    setState(() {
      final index = members.indexOf(oldMember);
      if (index != -1) {
        members[index] = updatedMember;
      }
    });
  }

  void removeMember(Map<String, dynamic> member) {
    setState(() {
      members.remove(member);
    });
  }

  @override
  Widget build(BuildContext context) {
    final filteredMembers = members.where((member) {
      final search = searchTerm.toLowerCase();
      return member.values.any((value) =>
          value.toString().toLowerCase().contains(search));
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            children: [
              Expanded(
                child: SearchBarWidget(
                  onChanged: (value) {
                    setState(() {
                      searchTerm = value;
                    });
                  },
                  hintText: "Search members...",
                  borderRadius: 12,
                  contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                ),
              ),
              const SizedBox(width: 8),
              CustomElevatedButton(
                icon: const Icon(Icons.person_add, color: Colors.white),
                label: const Text(
                  "Add Member",
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (context) => AddMemberDialog(
                      onMemberAdded: addMember,
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: SizedBox(
            width: double.infinity,
            child: Theme(
              data: Theme.of(context).copyWith(
                cardTheme: CardThemeData(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(color: Colors.grey.shade300, width: 1),
                  ),
                  color: Colors.white,
                ),
              ),
              child: PaginatedDataTable(
                headingRowColor: WidgetStateProperty.all(Colors.blueGrey[50]),
                columnSpacing: 40,
                rowsPerPage: 7,
                columns: const [
                  DataColumn(label: Text('Last Name')),
                  DataColumn(label: Text('First Name')),
                  DataColumn(label: Text('Middle Name')),
                  DataColumn(label: Text('Role')),
                  DataColumn(label: Text('Contact No.')),
                  DataColumn(label: Text('Birthday')),
                  DataColumn(label: Text('Address')),
                ],
                source: _MembersDataSource(filteredMembers, widget.onRowSelected),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _MembersDataSource extends DataTableSource {
  final List<Map<String, dynamic>> members;
  final Function(Map<String, dynamic>) onRowSelected;

  _MembersDataSource(this.members, this.onRowSelected);

  @override
  DataRow getRow(int index) {
    if (index >= members.length) return const DataRow(cells: []);
    final member = members[index];
    final isEven = index % 2 == 0;
    return DataRow(
      color: WidgetStateProperty.resolveWith<Color?>(
        (Set<WidgetState> states) {
          if (isEven) return Colors.grey[100];
          return null;
        },
      ),
      onSelectChanged: (_) => onRowSelected(member),
      cells: [
        DataCell(Text(member["lastName"] ?? "")),
        DataCell(Text(member["firstName"] ?? "")),
        DataCell(Text(member["middleName"] ?? "")),
        DataCell(Text(member["role"] ?? "")),
        DataCell(Text(member["contactNo"] ?? "")),
        DataCell(Text(member["birthday"] ?? "")),
        DataCell(Text(member["address"] ?? "")),
      ],
    );
  }

  @override
  bool get isRowCountApproximate => false;

  @override
  int get rowCount => members.length;

  @override
  int get selectedRowCount => 0;
}
