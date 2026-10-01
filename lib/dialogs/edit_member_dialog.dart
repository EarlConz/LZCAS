// lib/dialogs/edit_member_dialog.dart
//
// Edit Member, from the "Staff Modals Redesign" canvas. A dialog on
// desktop, a full screen on a phone (widgets/modal_kit.dart). The package
// can only be kept or removed here (removal = demotion, confirmed in the
// danger zone); what is handed to onMemberUpdated is unchanged.

import 'package:flutter/material.dart';
import 'package:lzcas/dialogs/birthday_picker_dialog.dart';
import 'package:lzcas/db/db.dart' show repository, Member, Package;
import 'package:lzcas/utils/phone_formatter.dart';
import 'package:lzcas/theme.dart';
import 'package:lzcas/utils/fonts.dart';
import 'package:lzcas/widgets/modal_kit.dart';

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

  // ── Change tracking ────────────────────────────────────────────────

  /// Field values when the dialog opened, to count unsaved changes.
  late final Map<String, Object?> _initial = _snapshot();

  /// Set once the demotion was confirmed (from the danger zone), so Save
  /// doesn't ask a second time.
  bool _demoteConfirmed = false;

  Map<String, Object?> _snapshot() => {
    'last': lastNameController.text.trim(),
    'first': firstNameController.text.trim(),
    'middle': middleNameController.text.trim(),
    'contact': contactController.text.replaceAll(' ', '').trim(),
    'birthday': birthdayController.text.trim(),
    'address': addressController.text.trim(),
    'referrer': _selectedReferrerId,
    'package': _selectedPackageId,
  };

  int get _changeCount {
    final now = _snapshot();
    return now.keys.where((k) => now[k] != _initial[k]).length;
  }

  Future<void> _askDemote() async {
    final ok = await confirmDestructive(
      context,
      title: 'Demote to Member?',
      message: 'Removing the package demotes this Verified Reseller back to a '
          'standard Member and revokes their reseller access. It takes effect '
          'when you save.',
      confirmLabel: 'Demote',
      cancelLabel: 'Keep reseller',
      icon: Icons.person_remove_outlined,
    );
    if (!ok || !mounted) return;
    setState(() {
      _selectedPackageId = null;
      _demoteConfirmed = true;
    });
  }

  // ── UI ─────────────────────────────────────────────────────────────

  String _memberName(Member m) => '${m.firstName ?? ''} ${m.lastName ?? ''}'.trim();

  String get _initials {
    String first(String? s) => (s ?? '').trim().isEmpty ? '' : s!.trim()[0].toUpperCase();
    final i = '${first(widget.member['firstName']?.toString())}${first(widget.member['lastName']?.toString())}';
    return i.isEmpty ? '?' : i;
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final muted = dark ? StockpileColors.darkTextMuted : const Color(0xFF6E6E7A);
    final screenW = MediaQuery.sizeOf(context).width;
    final fullName = '${widget.member['firstName'] ?? ''} ${widget.member['lastName'] ?? ''}'.trim();
    final memberId = widget.member['id'];
    final wasReseller = _originalPackageId != null;
    final changes = _changeCount;

    return AppModal(
      title: fullName.isEmpty ? 'Edit member' : fullName,
      subtitle: [
        wasReseller ? 'Verified Reseller' : 'Member',
        if (memberId != null) 'Member #$memberId',
      ].join(' · '),
      leading: CircleAvatar(
        radius: 24,
        backgroundColor: dark ? StockpileColors.darkTextPrimary : StockpileColors.darkText,
        foregroundColor: dark ? StockpileColors.darkBg : Colors.white,
        child: Text(_initials, style: StockpileFonts.satoshi(fontSize: 16, fontWeight: FontWeight.w700)),
      ),
      maxWidth: 760,
      body: [
        ModalSection(
          title: 'Personal',
          children: [
            FieldPair(
              LabeledField(
                label: 'Last name',
                required: true,
                child: TextFormField(
                  key: _lastNameKey,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  controller: lastNameController,
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  onChanged: (_) => setState(() {}),
                ),
              ),
              LabeledField(
                label: 'First name',
                required: true,
                child: TextFormField(
                  key: _firstNameKey,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  controller: firstNameController,
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ),
            FieldPair(
              LabeledField(
                label: 'Middle name',
                child: TextFormField(
                  controller: middleNameController,
                  decoration: const InputDecoration(hintText: 'Optional'),
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  onChanged: (_) => setState(() {}),
                ),
              ),
              LabeledField(
                label: 'Birthday',
                child: TextFormField(
                  controller: birthdayController,
                  readOnly: true,
                  onTap: () async {
                    await _pickBirthday();
                    if (mounted) setState(() {});
                  },
                  decoration: const InputDecoration(
                    hintText: 'Tap to pick',
                    suffixIcon: Icon(Icons.calendar_month_outlined),
                  ),
                ),
              ),
              keepPaired: true,
            ),
          ],
        ),
        ModalSection(
          title: 'Contact',
          children: [
            FieldPair(
              LabeledField(
                label: 'Contact number',
                child: TextFormField(
                  key: _contactKey,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  controller: contactController,
                  validator: (v) {
                    if (v != null && v.trim().isNotEmpty && !RegExp(r'^[0-9 ]+$').hasMatch(v.trim())) {
                      return 'Numbers only';
                    }
                    return null;
                  },
                  inputFormatters: [PhilippinePhoneFormatter()],
                  decoration: const InputDecoration(hintText: '0912 345 6789'),
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.next,
                  onChanged: (_) => setState(() {}),
                ),
              ),
              LabeledField(
                label: 'Address',
                child: TextFormField(
                  controller: addressController,
                  decoration: const InputDecoration(hintText: 'Optional'),
                  textInputAction: TextInputAction.next,
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ),
          ],
        ),
        ModalSection(
          title: 'Membership',
          children: [
            FieldPair(
              LabeledField(
                label: 'Package',
                // Read-only: edit may only keep or remove the package (the
                // danger zone below), never add or change one. Upgrades go
                // through Package Upgrade, which applies rank rules and pays
                // the referral bonus.
                child: InputDecorator(
                  decoration: const InputDecoration(enabled: false),
                  child: Text(
                    !wasReseller
                        ? 'None — standard Member'
                        : _selectedPackageId == null
                        ? 'None (after you save)'
                        : _currentPackageLabel().replaceAll(' (keep)', ''),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              LabeledField(label: 'Referred by', child: _referrerField(screenW)),
            ),
            Text(
              wasReseller
                  ? 'To change their package tier, use Package Upgrade.'
                  : 'To enroll them in a package, use Package Upgrade: it applies '
                        'rank rules and pays the referral bonus.',
              style: StockpileFonts.satoshi(fontSize: 12, color: muted),
            ),
          ],
        ),
        if (wasReseller)
          _demoteConfirmed
              ? Row(
                  children: [
                    const Expanded(
                      child: ModalNote(
                        tone: ModalTone.danger,
                        icon: Icons.person_remove_outlined,
                        title: 'Will be demoted to Member',
                        body: 'when you save.',
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () => setState(() {
                        _selectedPackageId = _originalPackageId;
                        _demoteConfirmed = false;
                      }),
                      child: const Text('Undo'),
                    ),
                  ],
                )
              : DangerZone(
                  title: 'Demote to Member',
                  body: 'Takes away the reseller role. You\'ll be asked to confirm.',
                  actionLabel: 'Demote…',
                  onPressed: _askDemote,
                ),
      ],
      footerNote: Text(
        changes == 0
            ? 'No changes yet'
            : '$changes change${changes == 1 ? '' : 's'} not saved',
        style: StockpileFonts.satoshi(fontSize: 12, color: muted),
      ),
      primaryAction: FilledButton(
        onPressed: changes == 0 ? null : _submit,
        child: const Text('Save changes'),
      ),
    );
  }

  /// Search members by name (never this member); suggestions show how many
  /// each has already referred. Opens on the current referrer's name.
  Widget _referrerField(double screenW) {
    return Autocomplete<Member>(
      initialValue: TextEditingValue(text: referrerSearchController.text),
      optionsBuilder: (value) {
        if (value.text.isEmpty) return const Iterable<Member>.empty();
        final query = value.text.toLowerCase();
        final memberId = widget.member['id'] as int?;
        return _members.where(
          (m) => m.id != memberId && _memberName(m).toLowerCase().contains(query),
        );
      },
      displayStringForOption: _memberName,
      fieldViewBuilder: (context, controller, focusNode, onSubmit) {
        return TextFormField(
          controller: controller,
          focusNode: focusNode,
          decoration: InputDecoration(
            hintText: 'Search a member',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: _selectedReferrerId != null
                ? IconButton(
                    tooltip: 'Clear',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () {
                      controller.clear();
                      referrerSearchController.clear();
                      setState(() => _selectedReferrerId = null);
                    },
                  )
                : null,
          ),
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(12),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: 220,
                maxWidth: (screenW - 32).clamp(200.0, 360.0),
              ),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (context, index) {
                  final m = options.elementAt(index);
                  final count = _referralCounts[m.id] ?? 0;
                  return ListTile(
                    dense: true,
                    minTileHeight: 44,
                    title: Text(_memberName(m), overflow: TextOverflow.ellipsis),
                    subtitle: count > 0
                        ? Text('$count referral${count == 1 ? '' : 's'}')
                        : null,
                    onTap: () => onSelected(m),
                  );
                },
              ),
            ),
          ),
        );
      },
      onSelected: (m) {
        referrerSearchController.text = _memberName(m);
        setState(() => _selectedReferrerId = m.id);
      },
    );
  }

  Future<void> _submit() async {
    if (!_validateAll()) return;

    // Removing an existing package demotes a Verified Reseller — confirm it,
    // since it stops their reseller income and revokes their access.
    final isDemotion = _originalPackageId != null && _selectedPackageId == null;
    // Normally confirmed already, from the danger zone. Asked here only if
    // the package was removed some other way.
    if (isDemotion && !_demoteConfirmed) {
      final confirmed = await confirmDestructive(
        context,
        title: 'Demote to Member?',
        message: 'Removing the package demotes this Verified Reseller back to a '
            'standard Member and revokes their reseller access.',
        confirmLabel: 'Demote',
        cancelLabel: 'Keep reseller',
        icon: Icons.person_remove_outlined,
      );
      if (!confirmed || !mounted) return;
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
