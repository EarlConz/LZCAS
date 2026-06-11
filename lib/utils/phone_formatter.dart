import 'package:flutter/services.dart';

/// Formats a Philippine phone number as the user types:
///   0912 345 6789   (mobile)
///   02 1234 5678    (landline, 2-digit area code)
///   032 123 4567    (landline, 3-digit area code)
class PhilippinePhoneFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return newValue.copyWith(text: '');

    // Cap at 11 digits (standard PH mobile max)
    final capped = digits.length > 11 ? digits.substring(0, 11) : digits;

    String formatted;
    if (capped.startsWith('09')) {
      // Mobile: 0912 345 6789
      formatted = _insertSpaces(capped, [4, 7]);
    } else if (capped.startsWith('02')) {
      // Manila landline: 02 1234 5678
      formatted = _insertSpaces(capped, [2, 6]);
    } else if (capped.length >= 3) {
      // Provincial landline: 032 123 4567
      formatted = _insertSpaces(capped, [3, 6]);
    } else {
      formatted = capped;
    }

    // Keep cursor at end
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
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
