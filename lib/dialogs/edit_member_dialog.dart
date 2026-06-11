import 'package:flutter/material.dart';
import 'package:lzcas/dialogs/birthday_picker_dialog.dart';
import 'package:lzcas/db/db.dart' show repository, Member;
import 'package:lzcas/utils/phone_formatter.dart';

class EditMemberDialog extends StatefulWidget {
  final Map<String, dynamic> member;
  final ValueChanged<Map<String, dynamic>> onMemberUpdated;

  const EditMemberDialog({
    super.key,
    required this.member,
    required this.onMemberUpdated,
  });

  @override
  State<EditMemberDialog> createState() => _EditMemberDialogState();
}

class _EditMemberDialogState extends State<EditMemberDialog> {
  late final TextEditingController lastNameController;
  late final TextEditingController firstNameController;
  late final TextEditingController middleNameController;
  late final TextEditingController contactController;
  late final TextEditingController birthdayController;
  late final TextEditingController addressController;
  late final TextEditingController pointsController;
  late String _roleValue;
  List<Member> _members = [];
  int? _selectedReferrerId;

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
    lastNameController = TextEditingController(
      text: widget.member['lastName']?.toString() ?? '',
    );
    firstNameController = TextEditingController(
      text: widget.member['firstName']?.toString() ?? '',
    );
    middleNameController = TextEditingController(
      text: widget.member['middleName']?.toString() ?? '',
    );
    _roleValue = widget.member['role']?.toString() ?? 'Member';
    contactController = TextEditingController(
      text: _formatPhone(widget.member['contactNo']?.toString() ?? ''),
    );
    birthdayController = TextEditingController(
      text: widget.member['birthday']?.toString() ?? '',
    );
    addressController = TextEditingController(
      text: widget.member['address']?.toString() ?? '',
    );
    pointsController = TextEditingController(
      text: widget.member['points']?.toString() ?? '0',
    );
    _selectedReferrerId = widget.member['referrerId'] as int?;
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
    pointsController.dispose();
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
    final memberId = widget.member['id'] as int?;
    final excludeSelf = _members.where((m) => m.id != memberId).toList();

    final inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
    );

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Icon(Icons.edit_note_rounded, color: colorScheme.primary, size: 28),
          const SizedBox(width: 10),
          Text(
            'Edit Member',
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
              // ── Role & status section ─────────────────────
              _sectionLabel('Role & Status', theme, colorScheme),
              const SizedBox(height: 10),
              TextFormField(
                initialValue: _roleValue,
                readOnly: true,
                decoration: InputDecoration(
                  labelText: 'Role',
                  prefixIcon: const Icon(Icons.shield_outlined),
                  border: inputBorder,
                  filled: true,
                  fillColor: colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.5,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: pointsController,
                decoration: InputDecoration(
                  labelText: 'Points',
                  prefixIcon: const Icon(Icons.stars_outlined),
                  border: inputBorder,
                ),
                keyboardType: TextInputType.number,
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
                  ...excludeSelf.map((m) {
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
                onChanged: (v) => setState(() => _selectedReferrerId = v),
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
          icon: const Icon(Icons.save, size: 18),
          label: const Text('Save'),
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

    final updatedMember = {
      'firstName': firstNameController.text.trim(),
      'middleName': middleNameController.text.trim(),
      'lastName': lastNameController.text.trim(),
      'role': _roleValue,
      'contactNo': contactController.text.trim().isEmpty
          ? null
          : contactController.text.replaceAll(' ', '').trim(),
      'birthday': birthdayController.text.trim(),
      'address': addressController.text.trim(),
      'points': int.tryParse(pointsController.text) ?? 0,
      'referrer': _selectedReferrerId != null
          ? (_members
                .firstWhere(
                  (m) => m.id == _selectedReferrerId,
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
                )
                .let((m) => '${m.firstName ?? ''} ${m.lastName ?? ''}'.trim()))
          : '',
      'referrerId': _selectedReferrerId,
    };

    widget.onMemberUpdated(updatedMember);
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

  /// Pre-format a raw digits-only phone number for display in the field.
  String _formatPhone(String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return '';
    if (digits.startsWith('09')) {
      return _insertSpaces(digits, [4, 7]);
    } else if (digits.startsWith('02')) {
      return _insertSpaces(digits, [2, 6]);
    } else if (digits.length >= 3) {
      return _insertSpaces(digits, [3, 6]);
    }
    return digits;
  }

  String _insertSpaces(String digits, List<int> positions) {
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (positions.contains(i)) buffer.write(' ');
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }
}

// ── Small extension for cleaner null-safe chaining ───────────────────
extension _Let<T> on T {
  R let<R>(R Function(T it) f) => f(this);
}
