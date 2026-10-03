// lib/dialogs/add_member_dialog.dart
//
// Add Member, from the "Staff Modals Redesign" canvas: Personal, Contact,
// Membership and Login account sections. A dialog on desktop, a full
// screen on a phone (widgets/modal_kit.dart). Validation and what is
// handed to onMemberAdded are unchanged.

import 'package:flutter/material.dart';
import 'package:lzcas/dialogs/birthday_picker_dialog.dart';
import 'package:lzcas/db/db.dart' show repository, Member, Package;
import 'package:lzcas/utils/phone_formatter.dart';
import 'package:lzcas/theme.dart';
import 'package:lzcas/utils/fonts.dart';
import 'package:lzcas/utils/toast_utils.dart';
import 'package:lzcas/utils/member_search.dart';
import 'package:lzcas/widgets/modal_kit.dart';
import 'package:lzcas/widgets/address_field.dart';

class AddMemberDialog extends StatefulWidget {
  final Future<int?> Function(Map<String, dynamic>) onMemberAdded;

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
  final referrerSearchController = TextEditingController();
  final usernameController = TextEditingController();
  final passwordController = TextEditingController();
  final _referrerSearch = MemberSearch();
  List<Package> _packages = [];
  final Map<int, int> _referralCounts = {};
  int? _selectedReferrerId;

  /// What is typed in Referred by. A name typed but never picked from the
  /// list links no one, so saving is held until it is picked or cleared
  /// (Part 3, G2: a referrer typed but not picked got no commission).
  String _referrerTyped = '';
  final _referrerKey = GlobalKey<FormFieldState>();
  int? _selectedPackageId;
  bool _createAccount = false;
  bool _obscurePassword = true;
  bool _submitting = false;

  final _lastNameKey = GlobalKey<FormFieldState>();
  final _firstNameKey = GlobalKey<FormFieldState>();
  final _contactKey = GlobalKey<FormFieldState>();
  final _usernameKey = GlobalKey<FormFieldState>();
  final _passwordKey = GlobalKey<FormFieldState>();

  /// A package makes this member a Verified Reseller, and reseller records
  /// are tied to a login account — so a package makes the account mandatory.
  bool get _accountRequired => _selectedPackageId != null;

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
    final packages = await repository.fetchPackages();
    if (!mounted) return;
    setState(() => _packages = packages);
  }

  /// Referrer suggestions, asked of the database as you type, each with how
  /// many members they referred (fetched for the suggestions only). This
  /// form used to download every member to search and count.
  Future<Iterable<Member>> _referrerOptions(String text) async {
    final found = await _referrerSearch(text, exclude: const {});
    final missing = found
        .map((m) => m.id)
        .whereType<int>()
        .where((id) => !_referralCounts.containsKey(id))
        .toList();
    if (missing.isNotEmpty) {
      try {
        final counts = await repository.referralCountsFor(missing);
        for (final id in missing) {
          _referralCounts[id] = counts[id] ?? 0;
        }
      } catch (_) {}
    }
    return found;
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
    usernameController.dispose();
    passwordController.dispose();
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
    // Account: username + password required whenever an account is created
    // (which is mandatory once a package is selected).
    if (_createAccount) {
      if (usernameController.text.trim().isEmpty) {
        _usernameKey.currentState?.validate();
        valid = false;
      }
      if (passwordController.text.isEmpty) {
        _passwordKey.currentState?.validate();
        valid = false;
      }
    }
    return valid;
  }

  // ── UI ─────────────────────────────────────────────────────────────

  String _memberName(Member m) => '${m.firstName ?? ''} ${m.lastName ?? ''}'.trim();

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final muted = dark ? StockpileColors.darkTextMuted : const Color(0xFF6E6E7A);
    final screenW = MediaQuery.sizeOf(context).width;

    return AppModal(
      title: 'Add member',
      subtitle: 'Fields marked * are required.',
      leading: const ModalIconTile(Icons.person_add_alt_1_outlined),
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
                  decoration: const InputDecoration(hintText: 'e.g. Dela Cruz'),
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
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
                  decoration: const InputDecoration(hintText: 'e.g. Juan'),
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
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
                ),
              ),
              LabeledField(
                label: 'Birthday',
                child: TextFormField(
                  controller: birthdayController,
                  readOnly: true,
                  onTap: _pickBirthday,
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
                ),
              ),
              LabeledField(
                label: 'Address',
                child: AddressField(controller: addressController),
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
                child: DropdownButtonFormField<int?>(
                  isExpanded: true,
                  initialValue: _selectedPackageId,
                  items: [
                    const DropdownMenuItem<int?>(
                      value: null,
                      child: Text('None — standard Member', overflow: TextOverflow.ellipsis),
                    ),
                    ..._packages.map(
                      (p) => DropdownMenuItem<int?>(
                        value: p.id,
                        child: Text('${p.name} — ₱${p.price}', overflow: TextOverflow.ellipsis),
                      ),
                    ),
                  ],
                  onChanged: (v) => setState(() {
                    _selectedPackageId = v;
                    // Reseller records need a login account — force it on.
                    if (v != null) _createAccount = true;
                  }),
                ),
              ),
              LabeledField(label: 'Referred by', child: _referrerField(screenW)),
            ),
            if (_selectedPackageId != null)
              const ModalNote(
                tone: ModalTone.info,
                icon: Icons.verified_outlined,
                title: 'Joins as a Verified Reseller.',
                body: 'A login account is required, and a transaction record is '
                    'created for the package.',
              ),
          ],
        ),
        ModalSection(
          title: 'Login account',
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Create a login for this member', style: StockpileFonts.satoshi(fontSize: 14)),
                      if (_accountRequired)
                        Text('Required for resellers', style: StockpileFonts.satoshi(fontSize: 12, color: muted)),
                    ],
                  ),
                ),
                Switch(
                  value: _createAccount,
                  // Locked on while a package is selected.
                  onChanged: _accountRequired ? null : (v) => setState(() => _createAccount = v),
                ),
              ],
            ),
            if (_createAccount)
              FieldPair(
                LabeledField(
                  label: 'Username',
                  required: true,
                  child: TextFormField(
                    key: _usernameKey,
                    controller: usernameController,
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    autocorrect: false,
                    validator: (v) =>
                        (_createAccount && (v ?? '').trim().isEmpty) ? 'Required' : null,
                    decoration: const InputDecoration(hintText: 'e.g. juandelacruz'),
                  ),
                ),
                LabeledField(
                  label: 'Password',
                  required: true,
                  child: TextFormField(
                    key: _passwordKey,
                    controller: passwordController,
                    obscureText: _obscurePassword,
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    validator: (v) => (_createAccount && (v ?? '').isEmpty) ? 'Required' : null,
                    decoration: InputDecoration(
                      hintText: 'Enter a password',
                      suffixIcon: IconButton(
                        tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                        icon: Icon(_obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                        onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
      primaryAction: FilledButton(
        onPressed: _submitting ? null : _submit,
        child: _submitting
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text('Add member'),
      ),
    );
  }

  /// Search members by name; the suggestions show how many each has
  /// already referred.
  Widget _referrerField(double screenW) {
    return Autocomplete<Member>(
      optionsBuilder: (value) => _referrerOptions(value.text),
      displayStringForOption: _memberName,
      fieldViewBuilder: (context, controller, focusNode, onSubmit) {
        return TextFormField(
          key: _referrerKey,
          controller: controller,
          focusNode: focusNode,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          validator: (_) => _referrerUnpicked
              ? 'Pick a name from the list, or clear it'
              : null,
          onChanged: (text) => setState(() {
            _referrerTyped = text.trim();
            // Typing over a picked name un-picks it.
            if (_referrerTyped != referrerSearchController.text.trim()) {
              _selectedReferrerId = null;
            }
          }),
          decoration: InputDecoration(
            hintText: 'Search a member',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: _selectedReferrerId != null || _referrerTyped.isNotEmpty
                ? IconButton(
                    tooltip: 'Clear',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () {
                      controller.clear();
                      setState(() {
                        _selectedReferrerId = null;
                        _referrerTyped = '';
                      });
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
              // Wide enough to read on a phone (it was 40% of the screen,
              // about 150 px), capped on desktop.
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
        setState(() {
          _selectedReferrerId = m.id;
          _referrerTyped = _memberName(m).trim();
        });
        _referrerKey.currentState?.validate();
      },
    );
  }

  bool get _referrerUnpicked =>
      _referrerTyped.isNotEmpty && _selectedReferrerId == null;

  Future<void> _submit() async {
    if (_submitting) return;
    if (!_validateAll()) return;
    if (_referrerUnpicked) {
      _referrerKey.currentState?.validate();
      showErrorToast('Pick the referrer from the list, or clear the field.');
      return;
    }
    setState(() => _submitting = true);

    final newMember = {
      'lastName': lastNameController.text.trim(),
      'firstName': firstNameController.text.trim(),
      'middleName': middleNameController.text.trim(),
      'contactNo': contactController.text.trim().isEmpty
          ? null
          : contactController.text.replaceAll(' ', '').trim(),
      'birthday': birthdayController.text.trim(),
      'address': addressController.text.trim(),
      // The name picked from the suggestions (set in onSelected).
      'referrer': _selectedReferrerId != null
          ? referrerSearchController.text.trim()
          : '',
      'referrerId': _selectedReferrerId,
      'role': 'Member',
      // A package registers the member as a Verified Reseller.
      'packageId': _selectedPackageId,
      'createAccount': _createAccount,
      'username': _createAccount ? usernameController.text.trim() : null,
      'password': _createAccount ? passwordController.text : null,
    };

    final memberId = await widget.onMemberAdded(newMember);
    if (memberId == null || memberId == 0) {
      if (mounted) setState(() => _submitting = false);
      return; // failure — dialog stays open
    }

    if (!mounted) return;
    Navigator.pop(context);
  }
}
