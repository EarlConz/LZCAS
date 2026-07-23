import 'package:flutter/material.dart';
import 'package:lzcas/dialogs/birthday_picker_dialog.dart';
import 'package:lzcas/db/db.dart' show repository, Member, Package;
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
  late final TextEditingController referrerSearchController;
  List<Member> _members = [];
  Map<int, int> _referralCounts = {};
  int? _selectedReferrerId;

  // Reseller status is derived purely from package availment.
  int? _selectedPackageId;
  List<Package> _packages = [];

  /// The package the member had when the dialog opened. Edit may only *keep*
  /// or *remove* this — adding or raising a package must go through the guarded
  /// Package Upgrade flow (rank rules + referral bonus), never here.
  int? _originalPackageId;

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
    contactController = TextEditingController(
      text: _formatPhone(widget.member['contactNo']?.toString() ?? ''),
    );
    birthdayController = TextEditingController(
      text: widget.member['birthday']?.toString() ?? '',
    );
    addressController = TextEditingController(
      text: widget.member['address']?.toString() ?? '',
    );
    _selectedReferrerId = widget.member['referrerId'] as int?;
    _selectedPackageId = widget.member['packageId'] as int?;
    _originalPackageId = _selectedPackageId;
    referrerSearchController = TextEditingController(
      text: widget.member['referrer']?.toString() ?? '',
    );
    _loadMembers();
    _loadPackages();
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

  Future<void> _loadPackages() async {
    final pkgs = await repository.fetchPackages();
    if (!mounted) return;
    setState(() => _packages = pkgs);
  }

  /// Reseller status is derived from package availment.
  bool get _isReseller => _selectedPackageId != null;

  /// Label for the member's current package in the (keep-only) dropdown.
  String _currentPackageLabel() {
    final match = _packages.where((p) => p.id == _originalPackageId);
    if (match.isNotEmpty) {
      return '${match.first.name} — ₱${match.first.price} (keep)';
    }
    return 'Current package (keep)';
  }

  @override
  void dispose() {
    lastNameController.dispose();
    firstNameController.dispose();
    middleNameController.dispose();
    contactController.dispose();
    birthdayController.dispose();
    addressController.dispose();
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
              // Role is derived from the package selection below.
              _sectionLabel('Role & Status', theme, colorScheme),
              const SizedBox(height: 10),
              TextFormField(
                key: ValueKey(_isReseller),
                initialValue: _isReseller ? 'Verified Reseller' : 'Member',
                readOnly: true,
                decoration: InputDecoration(
                  labelText: 'Role',
                  helperText: 'Set by the package below',
                  prefixIcon: const Icon(Icons.shield_outlined),
                  border: inputBorder,
                  filled: true,
                  fillColor: colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.5,
                  ),
                ),
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
              // ── Package section ────────────────────────────
              // A package registers the member as a Verified Reseller;
              // None keeps them a standard Member.
              _sectionLabel('Package', theme, colorScheme),
              const SizedBox(height: 10),
              DropdownButtonFormField<int?>(
                initialValue: _selectedPackageId,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'Package',
                  prefixIcon: const Icon(Icons.card_giftcard_outlined),
                  border: inputBorder,
                ),
                items: [
                  const DropdownMenuItem<int?>(
                    value: null,
                    child: Text(
                      'None (Standard Member)',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  // Edit may only keep the current package or remove it. No
                  // other package is offered — upgrades/downgrades must go
                  // through the guarded Package Upgrade flow so rank rules and
                  // the referral bonus always run.
                  if (_originalPackageId != null)
                    DropdownMenuItem<int?>(
                      value: _originalPackageId,
                      child: Text(
                        _currentPackageLabel(),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                // A member with no package can't gain one here; the field is
                // locked and they must be enrolled via the Upgrade flow.
                onChanged: _originalPackageId == null
                    ? null
                    : (v) => setState(() => _selectedPackageId = v),
              ),
              const SizedBox(height: 8),
              Builder(
                builder: (context) {
                  if (_originalPackageId == null) {
                    return Text(
                      'To enroll this member in a package, use the Package '
                      'Upgrade action — it applies rank rules and pays the '
                      'referral bonus.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontStyle: FontStyle.italic,
                      ),
                    );
                  }
                  if (_selectedPackageId == null) {
                    return Text(
                      '⚠ Removing the package demotes this Verified Reseller to '
                      'a standard Member and revokes reseller access.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.error,
                        fontStyle: FontStyle.italic,
                      ),
                    );
                  }
                  return Text(
                    'This member is a Verified Reseller. To change tiers, use '
                    'the Package Upgrade action instead.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.primary,
                      fontStyle: FontStyle.italic,
                    ),
                  );
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

  Future<void> _submit() async {
    if (!_validateAll()) return;

    // Removing an existing package demotes a Verified Reseller — confirm it,
    // since it stops their reseller income and revokes their access.
    final isDemotion = _originalPackageId != null && _selectedPackageId == null;
    if (isDemotion) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Demote to Member?'),
          content: const Text(
            'Removing the package demotes this Verified Reseller back to a '
            'standard Member and revokes their reseller access. Continue?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Demote'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }

    final updatedMember = {
      'firstName': firstNameController.text.trim(),
      'middleName': middleNameController.text.trim(),
      'lastName': lastNameController.text.trim(),
      // Role is derived from the package by MembersTable.updateMember.
      'role': _isReseller ? 'Verified Reseller' : 'Member',
      'contactNo': contactController.text.trim().isEmpty
          ? null
          : contactController.text.replaceAll(' ', '').trim(),
      'birthday': birthdayController.text.trim(),
      'address': addressController.text.trim(),
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

                    qr: null,
                  ),
                )
                .let((m) => '${m.firstName ?? ''} ${m.lastName ?? ''}'.trim()))
          : '',
      'referrerId': _selectedReferrerId,
      'packageId': _selectedPackageId,
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
