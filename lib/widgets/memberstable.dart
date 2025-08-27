import 'package:flutter/material.dart';

class MembersTable extends StatefulWidget {
  final String searchTerm;
  final Function(Map<String, dynamic>) onRowSelected;

  const MembersTable({
    super.key,
    required this.searchTerm,
    required this.onRowSelected,
  });

  @override
  MembersTableState createState() => MembersTableState();
}

class MembersTableState extends State<MembersTable> {
  final List<Map<String, dynamic>> members = [
    {
      "lastName": "Cruz",
      "firstName": "Juan",
      "middleName": "Dela",
      "role": "Leader",
      "contactNo": "09171234567",
      "birthday": "Jan 10, 1990",
      "address": "Quezon City",
      "referrer": "Reyes",   // ✅ new field
      "points": 15,          // ✅ always 15 by default
    },
    {
      "lastName": "Reyes",
      "firstName": "Maria",
      "middleName": "Lopez",
      "role": "Member",
      "contactNo": "09182345678",
      "birthday": "Feb 20, 1992",
      "address": "Makati City",
      "referrer": "Cruz",    // ✅ new field
      "points": 15,          // ✅ always 15
    },
    // add more for testing
  ];
    // add more for testing


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

  // ✅ NEW: remove member
  void removeMember(Map<String, dynamic> member) {
    setState(() {
      members.remove(member);
    });
  }

  @override
  Widget build(BuildContext context) {
    final filteredMembers = members.where((member) {
      final search = widget.searchTerm.toLowerCase();
      return member.values.any((value) =>
          value.toString().toLowerCase().contains(search));
    }).toList();

    return SizedBox(
      width: double.infinity, // make table take full width
      child: PaginatedDataTable(
        columnSpacing: 40,
        headingRowColor: MaterialStateProperty.all(Colors.grey.shade200),
        rowsPerPage: 7, // 🔥 pagination restored here
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
    return DataRow(
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