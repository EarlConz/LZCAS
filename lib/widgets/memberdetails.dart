import 'package:flutter/material.dart';
import 'memberqr.dart';

class MemberDetailsCard extends StatelessWidget {
  final Map<String, dynamic> member;

  const MemberDetailsCard({super.key, required this.member});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.2),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Member details on the left
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Name with avatar embedded inline so the icon follows the name text
                RichText(
                  text: TextSpan(
                    style: DefaultTextStyle.of(context).style.copyWith(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                    children: [
                      TextSpan(text: "${member['firstName']} ${member['middleName']} ${member['lastName']}"),
                      WidgetSpan(
                        alignment: PlaceholderAlignment.middle,
                        child: Padding(
                          padding: const EdgeInsets.only(left: 8.0),
                          child: MemberQr(
                            lastName: member['lastName'],
                            firstName: member['firstName'],
                            middleName: member['middleName'],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
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
                Text(
                  member['referrer'] != null &&
                          member['referrer'].toString().isNotEmpty
                      ? "Referrer: ${member['referrer']}"
                      : "Referrer: None",
                  style: const TextStyle(fontStyle: FontStyle.italic),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
