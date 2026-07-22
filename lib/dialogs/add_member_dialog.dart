import 'package:flutter/material.dart';
import 'package:lzcas/dialogs/birthday_picker_dialog.dart';
import 'package:lzcas/db/db.dart' show repository, Member, Package;
import 'package:lzcas/utils/phone_formatter.dart';

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
  List<Member> _members = [];
  List<Package> _packages = [];
  Map<int, int> _referralCounts = {};
  int? _selectedReferrerId;
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
    final rows = await repository.fetchMembers();
    final packages = await repository.fetchPackages();
    if (!mounted) return;
    setState(() {
      _members = rows;
      _packages = packages;
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isNarrow = MediaQuery.sizeOf(context).width < 500;

    final inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
    );

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      titlePadding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      title: Row(
        children: [
          Icon(Icons.person_add_rounded, color: colorScheme.primary, size: 30),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              'Add New Member',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: isNarrow ? double.maxFinite : 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Name section ──────────────────────────────
              _sectionLabel('Name', theme, colorScheme),
              const SizedBox(height: 12),
              TextFormField(
                key: _lastNameKey,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                controller: lastNameController,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
                decoration: InputDecoration(
                  label: const Text.rich(
                    TextSpan(
                      text: 'Last Name ',
                      children: [
                        TextSpan(
                          text: '*',
                          style: TextStyle(color: Colors.red),
                        ),
                      ],
                    ),
                  ),
                  hintText: 'e.g. Dela Cruz',
                  prefixIcon: const Icon(Icons.badge_outlined),
                  border: inputBorder,
                ),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: _firstNameKey,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                controller: firstNameController,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
                decoration: InputDecoration(
                  label: const Text.rich(
                    TextSpan(
                      text: 'First Name ',
                      children: [
                        TextSpan(
                          text: '*',
                          style: TextStyle(color: Colors.red),
                        ),
                      ],
                    ),
                  ),
                  hintText: 'e.g. Juan',
                  prefixIcon: const Icon(Icons.person_outline),
                  border: inputBorder,
                ),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 16),
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

              const SizedBox(height: 24),
              // ── Contact section ───────────────────────────
              _sectionLabel('Contact', theme, colorScheme),
              const SizedBox(height: 12),
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
              const SizedBox(height: 16),
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
              const SizedBox(height: 16),
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

              const SizedBox(height: 24),
              // ── Package section ────────────────────────────
              // Availing a package registers the member as a Verified
              // Reseller; no package means a standard Member.
              _sectionLabel('Package', theme, colorScheme),
              const SizedBox(height: 12),
              DropdownButtonFormField<int?>(
                isExpanded: true,
                initialValue: _selectedPackageId,
                decoration: InputDecoration(
                  labelText: 'Select Package',
                  hintText: 'Optional — leave as None for a standard Member',
                  prefixIcon: const Icon(Icons.card_giftcard_outlined),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                items: [
                  const DropdownMenuItem<int?>(
                    value: null,
                    child: Text(
                      'None (Standard Member)',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  ..._packages.map(
                    (p) => DropdownMenuItem<int?>(
                      value: p.id,
                      child: Text(
                        '${p.name} — ₱${p.price}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
                onChanged: (v) => setState(() {
                  _selectedPackageId = v;
                  // Reseller records need a login account — force it on.
                  if (v != null) _createAccount = true;
                }),
              ),
              if (_selectedPackageId != null) ...[
                const SizedBox(height: 8),
                Text(
                  '⚠ Selecting a package registers this member as a Verified '
                  'Reseller (requires a login account) and creates a '
                  'transaction record.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.primary,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],

              const SizedBox(height: 24),
              // ── Account section ───────────────────────────
              _sectionLabel(
                _accountRequired ? 'Account (Required)' : 'Account (Optional)',
                theme,
                colorScheme,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _accountRequired
                          ? 'A login account is required for reseller members'
                          : 'Create login account for this member',
                    ),
                  ),
                  Switch(
                    value: _createAccount,
                    // Locked on while a package is selected.
                    onChanged: _accountRequired
                        ? null
                        : (v) => setState(() => _createAccount = v),
                  ),
                ],
              ),
              if (_createAccount) ...[
                const SizedBox(height: 12),
                TextFormField(
                  key: _usernameKey,
                  controller: usernameController,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  validator: (v) => (_createAccount && (v ?? '').trim().isEmpty)
                      ? 'Required'
                      : null,
                  decoration: InputDecoration(
                    label: const Text.rich(
                      TextSpan(
                        text: 'Username ',
                        children: [
                          TextSpan(
                            text: '*',
                            style: TextStyle(color: Colors.red),
                          ),
                        ],
                      ),
                    ),
                    hintText: 'Enter a username',
                    prefixIcon: const Icon(Icons.person_outline),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: _passwordKey,
                  controller: passwordController,
                  obscureText: _obscurePassword,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  validator: (v) =>
                      (_createAccount && (v ?? '').isEmpty) ? 'Required' : null,
                  decoration: InputDecoration(
                    label: const Text.rich(
                      TextSpan(
                        text: 'Password ',
                        children: [
                          TextSpan(
                            text: '*',
                            style: TextStyle(color: Colors.red),
                          ),
                        ],
                      ),
                    ),
                    hintText: 'Enter a password',
                    prefixIcon: const Icon(Icons.lock_outlined),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_off
                            : Icons.visibility,
                      ),
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              // ── Referrer section ──────────────────────────
              _sectionLabel('Referral', theme, colorScheme),
              const SizedBox(height: 12),
              Autocomplete<Member>(
                optionsBuilder: (textEditingValue) {
                  if (textEditingValue.text.isEmpty) return [];
                  final query = textEditingValue.text.toLowerCase();
                  return _members.where((m) {
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
            ],
          ),
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
      actions: [
        OverflowBar(
          spacing: 12,
          overflowSpacing: 8,
          alignment: MainAxisAlignment.end,
          overflowAlignment: OverflowBarAlignment.end,
          children: [
            OutlinedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: _submitting ? null : _submit,
              icon: _submitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.person_add, size: 20),
              label: Text(_submitting ? 'Adding…' : 'Add Member'),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (!_validateAll()) return;
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
      'referrer': _selectedReferrerId != null
          ? () {
              final sel = _members.firstWhere(
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
              );
              return '${sel.firstName ?? ''} ${sel.lastName ?? ''}'.trim();
            }()
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

  Widget _sectionLabel(String text, ThemeData theme, ColorScheme colorScheme) {
    return Row(
      children: [
        Flexible(
          child: Text(
            text.toUpperCase(),
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleSmall?.copyWith(
              color: colorScheme.primary,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5,
            ),
          ),
        ),
        const SizedBox(width: 10),
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
