import 'dart:math';
import 'package:flutter/material.dart';

class MembersTable extends StatefulWidget {
  final String searchTerm;
  final ValueChanged<Map<String, dynamic>> onRowSelected;

  const MembersTable({
    super.key,
    required this.searchTerm,
    required this.onRowSelected,
  });

  @override
  State<MembersTable> createState() => _MembersTableState();
}

class _MembersTableState extends State<MembersTable> {
  int _rowsPerPage = 7;
  int _currentPage = 0;

  final List<Map<String, dynamic>> members = const [
    {
      "lastName": "Cruz",
      "firstName": "Juan",
      "middleName": "Dela",
      "role": "Leader",
      "contact": "09171234567",
      "birthday": "Jan 10, 1990",
      "address": "Quezon City",
      "points": 15,
      "referrer": "Pedro Santos",
    },
    {
      "lastName": "Reyes",
      "firstName": "Maria",
      "middleName": "Lopez",
      "role": "Member",
      "contact": "09182345678",
      "birthday": "Feb 20, 1992",
      "address": "Makati City",
      "points": 15,
      "referrer": "",
    },
    {
      "lastName": "Santos",
      "firstName": "Pedro",
      "middleName": "Garcia",
      "role": "Member",
      "contact": "09193456789",
      "birthday": "Mar 15, 1993",
      "address": "Pasig City",
      "points": 15,
      "referrer": "Juan Cruz",
    },
    {
      "lastName": "Torres",
      "firstName": "Ana",
      "middleName": "Villanueva",
      "role": "Leader",
      "contact": "09204567890",
      "birthday": "Apr 12, 1994",
      "address": "Caloocan City",
      "points": 15,
      "referrer": "",
    },
    {
      "lastName": "Dela Cruz",
      "firstName": "Jose",
      "middleName": "Ramos",
      "role": "Member",
      "contact": "09215678901",
      "birthday": "May 5, 1995",
      "address": "Taguig City",
      "points": 15,
      "referrer": "Maria Reyes",
    },
    {
      "lastName": "Velasquez",
      "firstName": "Carla",
      "middleName": "Santos",
      "role": "Member",
      "contact": "09326789012",
      "birthday": "Jun 18, 1996",
      "address": "Manila",
      "points": 20,
      "referrer": "Jose Dela Cruz",
    },
    {
      "lastName": "Gomez",
      "firstName": "Luis",
      "middleName": "Fernandez",
      "role": "Leader",
      "contact": "09437890123",
      "birthday": "Jul 22, 1991",
      "address": "Mandaluyong",
      "points": 30,
      "referrer": "",
    },
    {
      "lastName": "Ramos",
      "firstName": "Elena",
      "middleName": "Torres",
      "role": "Member",
      "contact": "09548901234",
      "birthday": "Aug 30, 1997",
      "address": "Las Piñas",
      "points": 12,
      "referrer": "Carla Velasquez",
    },
    {
      "lastName": "Navarro",
      "firstName": "Diego",
      "middleName": "Martinez",
      "role": "Member",
      "contact": "09659012345",
      "birthday": "Sep 14, 1998",
      "address": "Parañaque",
      "points": 18,
      "referrer": "Luis Gomez",
    },
    {
      "lastName": "Flores",
      "firstName": "Sofia",
      "middleName": "Gutierrez",
      "role": "Leader",
      "contact": "09760123456",
      "birthday": "Oct 5, 1999",
      "address": "Malabon",
      "points": 25,
      "referrer": "",
    },
  ];

  @override
  Widget build(BuildContext context) {
    // 🔎 Filter by name only
    final term = widget.searchTerm.toLowerCase();
    final filteredMembers = members.where((member) {
      final fullName =
          '${member["firstName"]} ${member["middleName"]} ${member["lastName"]}'.toLowerCase();
      return fullName.contains(term);
    }).toList();

    // ✅ Pagination bounds after filtering
    final totalPages = (filteredMembers.length / _rowsPerPage).ceil();
    if (totalPages == 0) {
      _currentPage = 0;
    } else if (_currentPage >= totalPages) {
      _currentPage = totalPages - 1;
    }

    final start = _currentPage * _rowsPerPage;
    final end = min(start + _rowsPerPage, filteredMembers.length);
    final pageItems = filteredMembers.sublist(start, end);

    return Column(
      children: [
        // 📋 Table with horizontal scroll
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Padding(
            padding: const EdgeInsets.only(right: 24.0),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minWidth: MediaQuery.of(context).size.width,
              ),
              child: DataTable(
                headingRowColor: MaterialStateProperty.all(Colors.grey[200]),
                columnSpacing: 20,
                columns: const [
                  DataColumn(label: Text('Last Name')),
                  DataColumn(label: Text('First Name')),
                  DataColumn(label: Text('Middle Name')),
                  DataColumn(label: Text('Role')),
                  DataColumn(label: Text('Contact No.')),
                  DataColumn(label: Text('Birthday')),
                  DataColumn(label: Text('Address')),
                ],
                rows: pageItems.map((member) {
                  return DataRow(
                    cells: [
                      DataCell(Text(member['lastName'].toString()),
                          onTap: () => widget.onRowSelected(member)),
                      DataCell(Text(member['firstName'].toString()),
                          onTap: () => widget.onRowSelected(member)),
                      DataCell(Text(member['middleName'].toString()),
                          onTap: () => widget.onRowSelected(member)),
                      DataCell(Text(member['role'].toString()),
                          onTap: () => widget.onRowSelected(member)),
                      DataCell(Text(member['contact'].toString()),
                          onTap: () => widget.onRowSelected(member)),
                      DataCell(Text(member['birthday'].toString()),
                          onTap: () => widget.onRowSelected(member)),
                      DataCell(
                        ConstrainedBox(
                          constraints: const BoxConstraints(minWidth: 220),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              member['address'].toString(),
                              softWrap: false,
                              overflow: TextOverflow.visible,
                            ),
                          ),
                        ),
                        onTap: () => widget.onRowSelected(member),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
        ),

        // 📌 Pagination bar pinned at bottom center
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                onPressed:
                    _currentPage > 0 ? () => setState(() => _currentPage--) : null,
                icon: const Icon(Icons.arrow_back),
              ),
              Text('Page ${totalPages == 0 ? 0 : _currentPage + 1} of $totalPages'),
              IconButton(
                onPressed: _currentPage < totalPages - 1
                    ? () => setState(() => _currentPage++)
                    : null,
                icon: const Icon(Icons.arrow_forward),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
