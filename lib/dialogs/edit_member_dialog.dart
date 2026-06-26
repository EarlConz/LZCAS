import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart' as fs;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:lzcas/dialogs/birthday_picker_dialog.dart';
import 'package:lzcas/db/db.dart' show repository, Member;
import 'package:lzcas/utils/phone_formatter.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

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
  late final TextEditingController idNumberController;
  late final TextEditingController referrerSearchController;
  late String _roleValue;
  late String? _selectedIdType;
  String? _selectedIdImagePath;
  List<Member> _members = [];
  Map<int, int> _referralCounts = {};
  int? _selectedReferrerId;

  final _lastNameKey = GlobalKey<FormFieldState>();
  final _firstNameKey = GlobalKey<FormFieldState>();
  final _contactKey = GlobalKey<FormFieldState>();

  static const _idTypes = [
    'Driver\'s License',
    'National ID (PhilSys)',
    'Passport',
    'UMID',
    'SSS ID',
    'GSIS eCard',
    'PhilHealth ID',
    'PRC License',
    'Postal ID',
    'Voter\'s ID',
    'Senior Citizen ID',
    'Other',
  ];

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
      text: widget.member['level']?.toString() ?? '1',
    );
    _selectedReferrerId = widget.member['referrerId'] as int?;
    _selectedIdType = widget.member['idType']?.toString();
    _selectedIdImagePath = widget.member['idImagePath']?.toString();
    idNumberController = TextEditingController(
      text: widget.member['idNumber']?.toString() ?? '',
    );
    referrerSearchController = TextEditingController(
      text: widget.member['referrer']?.toString() ?? '',
    );
    _loadMembers();
  }

  Future<void> _pickIdImage() async {
    final files = await fs.openFiles(
      acceptedTypeGroups: [
        const fs.XTypeGroup(
          label: 'Images',
          extensions: ['jpg', 'jpeg', 'png'],
        ),
      ],
    );
    if (files.isEmpty || !mounted) return;

    final xfile = files.first;

    if (kIsWeb) {
      try {
        final bytes = await xfile.readAsBytes();
        final ext = xfile.name.split('.').last.toLowerCase();
        final mime = ext == 'png' ? 'image/png' : 'image/jpeg';
        final base64 = base64Encode(bytes);
        setState(() => _selectedIdImagePath = 'data:$mime;base64,$base64');
      } catch (_) {
        setState(() => _selectedIdImagePath = null);
      }
      return;
    }

    // Native: read bytes and write to app documents directory
    try {
      final bytes = await xfile.readAsBytes();
      final docsDir = await getApplicationDocumentsDirectory();
      final memberIdDir = Directory(p.join(docsDir.path, 'member_ids'));
      if (!await memberIdDir.exists()) {
        await memberIdDir.create(recursive: true);
      }
      final memberId = widget.member['id'] as int? ?? 0;
      final ext = xfile.name.contains('.') ? p.extension(xfile.name) : '.jpg';
      final destPath = p.join(memberIdDir.path, '$memberId$ext');
      await File(destPath).writeAsBytes(bytes);
      setState(() => _selectedIdImagePath = destPath);
    } catch (_) {
      setState(() => _selectedIdImagePath = xfile.path);
    }
  }

  Future<void> _loadMembers() async {
    final rows = await repository.fetchMembers();
    if (!mounted) return;
    setState(() {
      _members = rows;
      // Compute referral counts: count how many members have each referrerId
      _referralCounts = {};
      for (final m in rows) {
        if (m.referrerId != null) {
          _referralCounts[m.referrerId!] =
              (_referralCounts[m.referrerId!] ?? 0) + 1;
        }
      }
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
    idNumberController.dispose();
    referrerSearchController.dispose();
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
                autovalidateMode: AutovalidateMode.onUserInteraction,
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
                autovalidateMode: AutovalidateMode.onUserInteraction,
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
              if ((widget.member['role'] ?? '') == 'Verified Reseller')
                TextFormField(
                  controller: pointsController,
                  decoration: InputDecoration(
                    labelText: 'Level (1-10)',
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
                autovalidateMode: AutovalidateMode.onUserInteraction,
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
              Autocomplete<Member>(
                optionsBuilder: (textEditingValue) {
                  if (textEditingValue.text.isEmpty) return [];
                  final query = textEditingValue.text.toLowerCase();
                  final memberId = widget.member['id'] as int?;
                  return _members.where((m) {
                    if (m.id == memberId) return false; // exclude self
                    final name = '${m.firstName ?? ''} ${m.lastName ?? ''}'
                        .toLowerCase();
                    return name.contains(query);
                  });
                },
                displayStringForOption: (m) =>
                    '${m.firstName ?? ''} ${m.lastName ?? ''}'.trim(),
                fieldViewBuilder: (context, controller, focusNode, onSubmit) {
                  return TextFormField(
                    controller: controller,
                    focusNode: focusNode,
                    decoration: InputDecoration(
                      labelText: 'Referrer',
                      hintText: 'Type a name to search...',
                      prefixIcon: const Icon(Icons.search_outlined),
                      suffixIcon: _selectedReferrerId != null
                          ? IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: () {
                                controller.clear();
                                setState(() => _selectedReferrerId = null);
                              },
                            )
                          : null,
                      border: inputBorder,
                    ),
                  );
                },
                optionsViewBuilder: (context, onSelected, options) {
                  return Align(
                    alignment: Alignment.topLeft,
                    child: Material(
                      elevation: 4,
                      borderRadius: BorderRadius.circular(10),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: 200,
                          maxWidth: MediaQuery.of(context).size.width * 0.4,
                        ),
                        child: ListView.builder(
                          padding: EdgeInsets.zero,
                          itemCount: options.length,
                          itemBuilder: (context, index) {
                            final m = options.elementAt(index);
                            final label =
                                '${m.firstName ?? ''} ${m.lastName ?? ''}'
                                    .trim();
                            final count = _referralCounts[m.id] ?? 0;
                            final display = count > 0
                                ? '$label • $count referral${count == 1 ? '' : 's'}'
                                : label;
                            return ListTile(
                              dense: true,
                              title: Text(
                                display,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onTap: () {
                                onSelected(m);
                                referrerSearchController.text = label;
                                setState(() => _selectedReferrerId = m.id);
                              },
                            );
                          },
                        ),
                      ),
                    ),
                  );
                },
                onSelected: (m) {
                  final label = '${m.firstName ?? ''} ${m.lastName ?? ''}'
                      .trim();
                  referrerSearchController.text = label;
                  setState(() => _selectedReferrerId = m.id);
                },
              ),

              const SizedBox(height: 20),
              // ── ID Verification section ────────────────────
              _sectionLabel('Verification ID', theme, colorScheme),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue:
                    _selectedIdType != null &&
                        _selectedIdType!.isNotEmpty &&
                        _idTypes.contains(_selectedIdType)
                    ? _selectedIdType
                    : null,
                decoration: InputDecoration(
                  labelText: 'ID Type',
                  hintText: 'Select ID type (optional)',
                  prefixIcon: const Icon(Icons.credit_card_outlined),
                  border: inputBorder,
                ),
                items: _idTypes
                    .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                    .toList(),
                onChanged: (v) => setState(() => _selectedIdType = v),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: idNumberController,
                decoration: InputDecoration(
                  labelText: 'ID Number',
                  hintText: 'Optional',
                  prefixIcon: const Icon(Icons.numbers_outlined),
                  border: inputBorder,
                ),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 14),
              InkWell(
                onTap: _pickIdImage,
                borderRadius: BorderRadius.circular(10),
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: 'ID Photo',
                    hintText: 'Tap to upload',
                    prefixIcon: const Icon(Icons.camera_alt_outlined),
                    border: inputBorder,
                  ),
                  child:
                      _selectedIdImagePath != null &&
                          _selectedIdImagePath!.isNotEmpty
                      ? Row(
                          children: [
                            Icon(
                              Icons.check_circle,
                              size: 18,
                              color: colorScheme.primary,
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                kIsWeb
                                    ? 'Image selected'
                                    : p.basename(_selectedIdImagePath!),
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall,
                              ),
                            ),
                          ],
                        )
                      : const Text(
                          'Tap to select ID photo',
                          style: TextStyle(color: Colors.grey),
                        ),
                ),
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
      'level': int.tryParse(pointsController.text) ?? 1,
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
                    level: 1,
                    qr: null,
                  ),
                )
                .let((m) => '${m.firstName ?? ''} ${m.lastName ?? ''}'.trim()))
          : '',
      'referrerId': _selectedReferrerId,
      'idType': _selectedIdType,
      'idNumber': idNumberController.text.trim().isEmpty
          ? null
          : idNumberController.text.trim(),
      'idImagePath': _selectedIdImagePath,
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
