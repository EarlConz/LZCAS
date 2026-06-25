import 'package:flutter/material.dart';
import '../widgets/memberstable.dart';

class SuppliersPage extends StatelessWidget {
  const SuppliersPage({super.key});

  @override
  Widget build(BuildContext context) {
    return MembersTable(
      onRowSelected: (_) {
        // Member selected from the Suppliers table
      },
    );
  }
}
