// ignore_for_file: unnecessary_underscores
import 'package:flutter/material.dart';
import 'memberqr.dart';
import 'package:lzcas/db/db.dart';

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
                  children: [
                    Expanded(child: Text("Role: ${member['role']}")),
                    const SizedBox(width: 12),
                    Text("Points: ${member['points']}", style: const TextStyle(fontWeight: FontWeight.w600)),
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
          const SizedBox(width: 16),
          // Transactions column on the right (referred members' transactions)
          SizedBox(
            width: 320,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Member\'s Transaction History', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                FutureBuilder<List<Sale>>(
                  future: repository.fetchSalesForReferrer((member['id'] ?? 0) as int),
                  builder: (context, snap) {
                    if (snap.connectionState == ConnectionState.waiting) return const SizedBox(height:100, child: Center(child:CircularProgressIndicator()));
                    if (!snap.hasData || snap.data!.isEmpty) return const Text('No transactions found for referred members.');
                    final sales = snap.data!;
                    return SizedBox(
                      height: 160,
                      child: ListView.separated(
                        itemCount: sales.length.clamp(0, 6),
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final s = sales[i];
                          return ListTile(
                            dense: true,
                            title: Text(s.itemName),
                            subtitle: Text('qty: ${s.quantity}  price: ${s.price} pts: ${s.points}'),
                            trailing: Text(s.timestamp.toIso8601String().split('T').first),
                          );
                        },
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
