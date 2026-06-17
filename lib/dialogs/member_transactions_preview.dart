// ...existing code...
import 'package:flutter/material.dart';
import 'package:lzcas/db/db.dart';

class MemberTransactionsPreview extends StatefulWidget {
  final int memberId;
  final List<MemberTransactionEntry> entries;
  final DbRepository repository;

  const MemberTransactionsPreview({
    super.key,
    required this.memberId,
    required this.entries,
    required this.repository,
  });

  @override
  State<MemberTransactionsPreview> createState() =>
      _MemberTransactionsPreviewState();
}

class _MemberTransactionsPreviewState extends State<MemberTransactionsPreview> {
  bool _committing = false;
  String? _result;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);

    return AlertDialog(
      title: const Text('Preview Imported Transactions'),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: size.width < 700 ? double.infinity : 600,
          maxHeight: size.height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: widget.entries.length,
                itemBuilder: (context, i) {
                  final e = widget.entries[i];
                  return ListTile(
                    title: Text(e.itemName),
                    subtitle: Text(
                      'qty: ${e.quantity}, price: ${e.price}, points: ${e.points}, ts: ${e.timestamp ?? 'now'}',
                    ),
                  );
                },
              ),
            ),
            if (_result != null)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text(
                  _result!,
                  style: const TextStyle(color: Colors.red),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _committing
              ? null
              : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _committing
              ? null
              : () async {
                  setState(() {
                    _committing = true;
                    _result = null;
                  });
                  final safeContext = context;
                  final err = await widget.repository.commitMemberTransactions(
                    widget.memberId,
                    widget.entries,
                  );
                  if (!mounted) return;
                  setState(() {
                    _committing = false;
                  });
                  if (err == null) {
                    // ignore: use_build_context_synchronously
                    Navigator.of(safeContext).pop(true);
                  } else {
                    setState(() {
                      _result = err;
                    });
                  }
                },
          child: _committing
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Commit'),
        ),
      ],
    );
  }
}
