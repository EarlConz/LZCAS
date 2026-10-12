import 'package:flutter/services.dart';

/// Formats a Philippine phone number as the user types:
///   0912 345 6789   (mobile)
///   02 1234 5678    (landline, 2-digit area code)
///   032 123 4567    (landline, 3-digit area code)
///
/// A mobile number typed the international way (+63 912 …) or without its
/// leading 0 (912 …) becomes 0912 … too. Before, "+63 912 345 6789" fell
/// through to the landline rule and read "639 123 45678" (Part 3, T3).
class PhilippinePhoneFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final formatted = formatPhilippinePhone(newValue.text);
    if (formatted.isEmpty) return newValue.copyWith(text: '');

    // Keep cursor at end
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

/// The digits of a Philippine number, mobile ones always starting 09:
/// "+63 917 123 4567", "639171234567" and "9171234567" all give
/// "09171234567". Capped at 11 digits (the length of a mobile number).
String philippinePhoneDigits(String raw) {
  var digits = raw.replaceAll(RegExp(r'\D'), '');
  if (digits.startsWith('639')) {
    digits = '0${digits.substring(2)}';
  } else if (digits.startsWith('9')) {
    digits = '0$digits';
  }
  return digits.length > 11 ? digits.substring(0, 11) : digits;
}

/// For display and for the form: "09171234567" → "0917 123 4567". Stored
/// numbers are digits only; this is how every screen should show them.
String formatPhilippinePhone(String raw) {
  final digits = philippinePhoneDigits(raw);
  if (digits.isEmpty) return '';
  if (digits.startsWith('09')) {
    // Mobile: 0912 345 6789
    return _insertSpaces(digits, [4, 7]);
  } else if (digits.startsWith('02')) {
    // Manila landline: 02 1234 5678
    return _insertSpaces(digits, [2, 6]);
  } else if (digits.length >= 3) {
    // Provincial landline: 032 123 4567
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
