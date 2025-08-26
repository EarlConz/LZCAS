import 'package:flutter/material.dart';

class MembersPage extends StatelessWidget {
  const MembersPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        "Members Page",
        style: Theme.of(context).textTheme.headlineMedium,
      ),
    );
  }
}