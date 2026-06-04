import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

final _birthdayFormat = DateFormat('yyyy-MM-dd');
final _monthFormat = DateFormat('MMMM yyyy');
final _weekdayFormat = DateFormat('EEE');

DateTime? parseBirthday(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  final raw = value.trim();
  final formats = [
    DateFormat('yyyy-MM-dd'),
    DateFormat('MM/dd/yyyy'),
    DateFormat('dd/MM/yyyy'),
    DateFormat('MMMM d, yyyy'),
  ];

  for (final format in formats) {
    try {
      return format.parseStrict(raw);
    } catch (_) {
      // Try the next known format.
    }
  }

  return DateTime.tryParse(raw);
}

String formatBirthday(DateTime date) => _birthdayFormat.format(date);

Future<String?> showBirthdayPickerDialog(
  BuildContext context, {
  String? initialValue,
}) async {
  final selected = await showDialog<DateTime>(
    context: context,
    builder: (_) => BirthdayPickerDialog(initialDate: parseBirthday(initialValue)),
  );

  if (selected == null) return null;
  if (selected.year == 1) return '';
  return formatBirthday(selected);
}

class BirthdayPickerDialog extends StatefulWidget {
  const BirthdayPickerDialog({super.key, this.initialDate});

  final DateTime? initialDate;

  @override
  State<BirthdayPickerDialog> createState() => _BirthdayPickerDialogState();
}

class _BirthdayPickerDialogState extends State<BirthdayPickerDialog> {
  late DateTime _visibleMonth;
  DateTime? _selectedDate;
  late int _selectedYear;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialDate ?? DateTime(2000);
    _selectedDate = widget.initialDate;
    _visibleMonth = DateTime(initial.year, initial.month);
    _selectedYear = initial.year;
  }

  void _changeMonth(int delta) {
    setState(() {
      _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month + delta);
      _selectedYear = _visibleMonth.year;
    });
  }

  void _changeYear(int year) {
    setState(() {
      _selectedYear = year;
      _visibleMonth = DateTime(year, _visibleMonth.month);
    });
  }

  void _changeMonthTo(int month) {
    setState(() {
      _visibleMonth = DateTime(_selectedYear, month);
    });
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  List<DateTime?> _calendarDays() {
    final first = DateTime(_visibleMonth.year, _visibleMonth.month);
    final daysInMonth = DateTime(_visibleMonth.year, _visibleMonth.month + 1, 0).day;
    final leadingBlanks = first.weekday % 7;
    final cells = <DateTime?>[
      ...List<DateTime?>.filled(leadingBlanks, null),
      ...List.generate(daysInMonth, (i) => DateTime(_visibleMonth.year, _visibleMonth.month, i + 1)),
    ];

    while (cells.length % 7 != 0) {
      cells.add(null);
    }
    return cells;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final today = DateTime.now();
    final weekdays = List.generate(7, (i) => DateTime(2024, 1, i + 7));

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Select Birthday',
                      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Clear birthday',
                    onPressed: () => Navigator.pop(context, DateTime(1)),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: 'Previous month',
                        onPressed: () => _changeMonth(-1),
                        icon: const Icon(Icons.chevron_left),
                      ),
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          initialValue: _selectedYear,
                          decoration: const InputDecoration(
                            labelText: 'Year',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                          items: [
                            for (var year = today.year; year >= 1900; year--)
                              DropdownMenuItem(
                                value: year,
                                child: Text(year.toString()),
                              ),
                          ],
                          onChanged: (year) {
                            if (year != null) _changeYear(year);
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          initialValue: _visibleMonth.month,
                          decoration: const InputDecoration(
                            labelText: 'Month',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                          items: [
                            for (var month = 1; month <= 12; month++)
                              DropdownMenuItem(
                                value: month,
                                child: Text(
                                  DateFormat('MMM').format(DateTime(2024, month)),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged: (month) {
                            if (month != null) _changeMonthTo(month);
                          },
                        ),
                      ),
                      IconButton(
                        tooltip: 'Next month',
                        onPressed: () => _changeMonth(1),
                        icon: const Icon(Icons.chevron_right),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _monthFormat.format(_visibleMonth),
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 7,
                mainAxisSpacing: 6,
                crossAxisSpacing: 6,
                childAspectRatio: 1.15,
                children: [
                  for (final day in weekdays)
                    Center(
                      child: Text(
                        _weekdayFormat.format(day).substring(0, 1),
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  for (final date in _calendarDays()) _DayCell(
                    date: date,
                    isToday: date != null && _isSameDay(date, today),
                    isSelected: date != null && _selectedDate != null && _isSameDay(date, _selectedDate!),
                    onTap: date == null
                        ? null
                        : () {
                            setState(() => _selectedDate = date);
                          },
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(context, DateTime(1)),
                    child: const Text('Clear'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _selectedDate == null ? null : () => Navigator.pop(context, _selectedDate),
                    child: const Text('Use Date'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.date,
    required this.isToday,
    required this.isSelected,
    required this.onTap,
  });

  final DateTime? date;
  final bool isToday;
  final bool isSelected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (date == null) return const SizedBox.shrink();

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: isSelected ? colorScheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isToday && !isSelected ? colorScheme.primary : Colors.transparent,
          ),
        ),
        child: Center(
          child: Text(
            date!.day.toString(),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: isSelected ? colorScheme.onPrimary : colorScheme.onSurface,
              fontWeight: isSelected || isToday ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}
