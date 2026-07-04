import 'dart:convert';
import 'dart:io';

import 'package:bot_toast/bot_toast.dart';
import 'package:file_selector/file_selector.dart' as fs;
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/material.dart';
import 'package:lzcas/dialogs/birthday_picker_dialog.dart';
import 'package:lzcas/db/db.dart' show repository, Member;
import 'package:lzcas/utils/phone_formatter.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

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
  final idNumberController = TextEditingController();
  final referrerSearchController = TextEditingController();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  List<Member> _members = [];
  Map<int, int> _referralCounts = {};
  int? _selectedReferrerId;
  String? _selectedIdType;
  String? _selectedIdImagePath;
  bool _createAccount = false;

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

  Future<void> _pickIdImage() async {
    // file_selector can throw MissingPluginException after hot reload
    // because Flutter method channels aren't re-registered.
    List<fs.XFile> files;
    try {
      files = await fs.openFiles(
        acceptedTypeGroups: [
          const fs.XTypeGroup(
            label: 'Images',
            extensions: ['jpg', 'jpeg', 'png'],
          ),
        ],
      );
    } catch (e) {
      debugPrint('[AddMemberDialog] openFiles failed (hot reload?): $e');
      if (mounted) {
        BotToast.showText(
          text: 'File picker unavailable. Please restart the app.',
        );
      }
      return;
    }
    if (files.isEmpty || !mounted) return;

    final xfile = files.first;

    if (kIsWeb) {
      // Web: read bytes and store as base64 data URL (dart:io File is unavailable)
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
      final ext = xfile.name.contains('.') ? p.extension(xfile.name) : '.jpg';
      final destPath = p.join(
        memberIdDir.path,
        'new_${DateTime.now().millisecondsSinceEpoch}$ext',
      );
      await File(destPath).writeAsBytes(bytes);
      setState(() => _selectedIdImagePath = destPath);
    } catch (_) {
      setState(() => _selectedIdImagePath = xfile.path);
    }
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
    idNumberController.dispose();
    referrerSearchController.dispose();
    emailController.dispose();
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
          Text(
            'Add New Member',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
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
                  labelText: 'Last Name',
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
                  labelText: 'First Name',
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
              // ── ID Verification section ────────────────────
              _sectionLabel('Verification ID', theme, colorScheme),
              const SizedBox(height: 12),
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
              const SizedBox(height: 16),
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
              const SizedBox(height: 16),
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

              const SizedBox(height: 24),
              // ── Account section ───────────────────────────
              _sectionLabel('Account (Optional)', theme, colorScheme),
              const SizedBox(height: 12),
              Row(
                children: [
                  Text('Create login account for this member'),
                  const Spacer(),
                  Switch(
                    value: _createAccount,
                    onChanged: (v) => setState(() => _createAccount = v),
                  ),
                ],
              ),
              if (_createAccount) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: emailController,
                  decoration: InputDecoration(
                    labelText: 'Email',
                    hintText: 'member@example.com',
                    prefixIcon: const Icon(Icons.email_outlined),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: passwordController,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    hintText: 'Enter a password',
                    prefixIcon: const Icon(Icons.lock_outlined),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  obscureText: true,
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
        OutlinedButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        const SizedBox(width: 12),
        FilledButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.person_add, size: 20),
          label: const Text('Add Member'),
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
                  level: 1,
                  qr: null,
                ),
              );
              return '${sel.firstName ?? ''} ${sel.lastName ?? ''}'.trim();
            }()
          : '',
      'referrerId': _selectedReferrerId,
      'role': 'Member',
      'idType': _selectedIdType,
      'idNumber': idNumberController.text.trim().isEmpty
          ? null
          : idNumberController.text.trim(),
      'idImagePath': _selectedIdImagePath,
      'createAccount': _createAccount,
      'email': _createAccount ? emailController.text.trim() : null,
      'password': _createAccount ? passwordController.text : null,
    };

    widget.onMemberAdded(newMember);
    Navigator.pop(context);
  }

  Widget _sectionLabel(String text, ThemeData theme, ColorScheme colorScheme) {
    return Row(
      children: [
        Text(
          text.toUpperCase(),
          style: theme.textTheme.titleSmall?.copyWith(
            color: colorScheme.primary,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.5,
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
