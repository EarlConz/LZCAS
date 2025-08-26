import 'package:flutter/material.dart';

class MemberDetailsCard extends StatelessWidget {
  final Map<String, dynamic> member;

  const MemberDetailsCard({super.key, required this.member});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "${member["firstName"]} ${member["middleName"]} ${member["lastName"]}",
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: _buildInfo("Role", member["role"])),
                Expanded(child: _buildInfo("Contact No.", member["contact"])),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: _buildInfo("Birthday", member["birthday"])),
                Expanded(child: _buildInfo("Address", member["address"])),
              ],
            ),
            const Divider(height: 20, thickness: 1),
            Row(
              children: [
                Expanded(child: _buildInfo("Loyalty Points", member["points"].toString())),
                Expanded(
                    child: _buildInfo(
                        "Referrer", member["referrer"].toString().isEmpty ? "—" : member["referrer"])),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfo(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w500)),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}