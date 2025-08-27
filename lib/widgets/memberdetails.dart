import 'package:flutter/material.dart';

class MemberDetailsCard extends StatelessWidget {
  final Map<String, dynamic> member;

  const MemberDetailsCard({
    super.key,
    required this.member,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity, // ✅ full width
      margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.2),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 👤 Name
          Text(
            "${member['firstName']} ${member['middleName']} ${member['lastName']}",
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),

          // ℹ️ Details
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Role: ${member['role']}"),
              Text("Points: ${member['points']}"),
            ],
          ),
          const SizedBox(height: 8),
          Text("Contact: ${member['contactNo']}"),
          Text("Birthday: ${member['birthday']}"),
          Text("Address: ${member['address']}"),
          const SizedBox(height: 8),

          // 🧑 Referrer
          Text(
            member['referrer'] != null && member['referrer'].toString().isNotEmpty
                ? "Referrer: ${member['referrer']}"
                : "Referrer: None",
            style: const TextStyle(fontStyle: FontStyle.italic),
          ),
        ],
      ),
    );
  }
}