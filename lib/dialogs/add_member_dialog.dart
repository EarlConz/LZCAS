import 'package:flutter/material.dart';
import 'package:lzcas/dialogs/birthday_picker_dialog.dart';
import 'package:lzcas/db/db.dart' show repository, Member;
import 'package:lzcas/utils/phone_formatter.dart';

class AddMemberDialog extends StatefulWidget {
  final Function(Map<String, dynamic>) onMemberAdded;

  const AddMemberDialog({super.key, required this.onMemberAdded});

  @override
  State<AddMemberDialog> createState() => _AddMemberDialogState();
}

class _AddMemberDialogState extends State<AddMemberDialog> {
  final lastNameController = TextEditingController();
  final firstNameController = TextEditingController();
  final middleNameController = TextEditingController();
  final contactController = TextEditingController();
  final birthdayController = TextEditingController();
  final addressController = TextEditingController();
  List<Member> _members = [];
  int? _selectedReferrerId;
  String _selectedReferrerName = '';

  final _lastNameKey = GlobalKey<FormFieldState>();
  final _firstNameKey = GlobalKey<FormFieldState>();
  final _contactKey = GlobalKey<FormFieldState>();

  Future<void> _pickBirthday() async {
    final birthday = await showBirthdayPickerDialog(
      context,
      initialValue: birthdayController.text,
    );
    if (birthday == null || !mounted) return;
    setState(() {
      birthdayController.text = birthday;
    });
  }

  @override
  void initState() {
    super.initState();
    _loadMembers();
  }

  Future<void> _loadMembers() async {
    final rows = await repository.fetchMembers();
    if (!mounted) return;
    setState(() {
      _members = rows;
    });
  }

  @override
  void dispose() {
    lastNameController.dispose();
    firstNameController.dispose();
    middleNameController.dispose();
    contactController.dispose();
    birthdayController.dispose();
    addressController.dispose();
    super.dispose();
  }

  bool _validateAll() {
    bool valid = true;
    if (lastNameController.text.trim().isEmpty) {
      _lastNameKey.currentState?.validate();
      valid = false;
    }
    if (firstNameController.text.trim().isEmpty) {
      _firstNameKey.currentState?.validate();
      valid = false;
    }
    // Contact: optional, but if filled must be digits only
    final contact = contactController.text.trim();
    if (contact.isNotEmpty && !RegExp(r'^[0-9 ]+$').hasMatch(contact)) {
      _contactKey.currentState?.validate();
      valid = false;
    }
    return valid;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isNarrow = MediaQuery.sizeOf(context).width < 500;

    final inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
    );

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Icon(Icons.person_add_rounded, color: colorScheme.primary, size: 28),
          const SizedBox(width: 10),
          Text(
            'Add New Member',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: isNarrow ? double.maxFinite : 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Name section ──────────────────────────────
              _sectionLabel('Name', theme, colorScheme),
              const SizedBox(height: 10),
              TextFormField(
                key: _lastNameKey,
                controller: lastNameController,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
                decoration: InputDecoration(
                  labelText: 'Last Name',
                  hintText: 'e.g. Dela Cruz',
                  prefixIcon: const Icon(Icons.badge_outlined),
                  border: inputBorder,
                ),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 14),
              TextFormField(
                key: _firstNameKey,
                controller: firstNameController,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
                decoration: InputDecoration(
                  labelText: 'First Name',
                  hintText: 'e.g. Juan',
                  prefixIcon: const Icon(Icons.person_outline),
                  border: inputBorder,
                ),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: middleNameController,
                decoration: InputDecoration(
                  labelText: 'Middle Name',
                  hintText: 'Optional',
                  prefixIcon: const Icon(Icons.person_outline),
                  border: inputBorder,
                ),
                textInputAction: TextInputAction.next,
              ),

              const SizedBox(height: 20),
              // ── Contact section ───────────────────────────
              _sectionLabel('Contact', theme, colorScheme),
              const SizedBox(height: 10),
              TextFormField(
                key: _contactKey,
                controller: contactController,
                validator: (v) {
                  if (v != null &&
                      v.trim().isNotEmpty &&
                      !RegExp(r'^[0-9 ]+$').hasMatch(v.trim())) {
                    return 'Numbers only';
                  }
                  return null;
                },
                inputFormatters: [PhilippinePhoneFormatter()],
                decoration: InputDecoration(
                  labelText: 'Contact No.',
                  hintText: '0912 345 6789',
                  prefixIcon: const Icon(Icons.phone_outlined),
                  border: inputBorder,
                ),
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: birthdayController,
                readOnly: true,
                onTap: _pickBirthday,
                decoration: InputDecoration(
                  labelText: 'Birthday',
                  hintText: 'Tap to pick',
                  prefixIcon: const Icon(Icons.cake_outlined),
                  suffixIcon: const Icon(Icons.calendar_month_outlined),
                  border: inputBorder,
                ),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: addressController,
                decoration: InputDecoration(
                  labelText: 'Address',
                  hintText: 'Optional',
                  prefixIcon: const Icon(Icons.home_outlined),
                  border: inputBorder,
                ),
                textInputAction: TextInputAction.next,
              ),

              const SizedBox(height: 20),
              // ── Referrer section ──────────────────────────
              _sectionLabel('Referral', theme, colorScheme),
              const SizedBox(height: 10),
              DropdownButtonFormField<int?>(
                initialValue: _selectedReferrerId,
                decoration: InputDecoration(
                  labelText: 'Referrer',
                  prefixIcon: const Icon(Icons.group_outlined),
                  border: inputBorder,
                ),
                items: [
                  const DropdownMenuItem<int?>(
                    value: null,
                    child: Text('None'),
                  ),
                  ..._members.map((m) {
                    final label = '${m.firstName ?? ''} ${m.lastName ?? ''}'
                        .trim();
                    return DropdownMenuItem<int?>(
                      value: m.id,
                      child: Text(
                        label.isEmpty ? 'ID:${m.id}' : label,
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }),
                ],
                onChanged: (v) {
                  setState(() {
                    _selectedReferrerId = v;
                    final sel = _members.firstWhere(
                      (m) => m.id == v,
                      orElse: () => Member(
                        id: 0,
                        lastName: null,
                        firstName: null,
                        middleName: null,
                        role: null,
                        contactNo: null,
                        birthday: null,
                        address: null,
                        referrer: null,
                        points: 0,
                        qr: null,
                      ),
                    );
                    _selectedReferrerName = sel.id == 0
                        ? ''
                        : '${sel.firstName ?? ''} ${sel.lastName ?? ''}'.trim();
                  });
                },
              ),
            ],
          ),
        ),
      ),
      actionsPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.pop(context),
          style: OutlinedButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          child: const Text('Cancel'),
        ),
        const SizedBox(width: 10),
        FilledButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.person_add, size: 18),
          label: const Text('Add Member'),
          style: FilledButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
      ],
    );
  }

  void _submit() {
    if (!_validateAll()) return;

    final newMember = {
      'lastName': lastNameController.text.trim(),
      'firstName': firstNameController.text.trim(),
      'middleName': middleNameController.text.trim(),
      'contactNo': contactController.text.trim().isEmpty
          ? null
          : contactController.text.replaceAll(' ', '').trim(),
      'birthday': birthdayController.text.trim(),
      'address': addressController.text.trim(),
      'referrer': _selectedReferrerName,
      'referrerId': _selectedReferrerId,
      'points': 0,
      'role': 'Member',
    };

    widget.onMemberAdded(newMember);
    Navigator.pop(context);
  }

  Widget _sectionLabel(String text, ThemeData theme, ColorScheme colorScheme) {
    return Row(
      children: [
        Text(
          text.toUpperCase(),
          style: theme.textTheme.labelMedium?.copyWith(
            color: colorScheme.primary,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Divider(
            color: colorScheme.outline.withValues(alpha: 0.3),
            endIndent: 4,
          ),
        ),
      ],
    );
  }
}
