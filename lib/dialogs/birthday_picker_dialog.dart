import 'package:flutter/cupertino.dart' show CupertinoPicker;
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

/// A calendar dialog on a wide screen; on a phone, a sheet from the bottom
/// with month, day and year wheels (Part 3, T3: paging a calendar back
/// decades with small day cells was hard on a phone).
Future<String?> showBirthdayPickerDialog(
  BuildContext context, {
  String? initialValue,
}) async {
  final initial = parseBirthday(initialValue);
  final phone = MediaQuery.sizeOf(context).width < 600;
  final selected = phone
      ? await showModalBottomSheet<DateTime>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          showDragHandle: true,
          builder: (_) => BirthdayWheelSheet(initialDate: initial),
        )
      : await showDialog<DateTime>(
          context: context,
          builder: (_) => BirthdayPickerDialog(initialDate: initial),
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
    final daysInMonth = DateTime(
      _visibleMonth.year,
      _visibleMonth.month + 1,
      0,
    ).day;
    final leadingBlanks = first.weekday % 7;
    final cells = <DateTime?>[
      ...List<DateTime?>.filled(leadingBlanks, null),
      ...List.generate(
        daysInMonth,
        (i) => DateTime(_visibleMonth.year, _visibleMonth.month, i + 1),
      ),
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
        constraints: BoxConstraints(
          maxWidth: 440,
          maxHeight: MediaQuery.of(context).size.height * 0.80,
        ),
        child: ClipRect(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Select Birthday',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      iconSize: 28,
                      tooltip: 'Clear birthday',
                      onPressed: () => Navigator.pop(context, DateTime(1)),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 10, 8, 12),
                    child: Row(
                      children: [
                        IconButton(
                          iconSize: 28,
                          tooltip: 'Previous month',
                          onPressed: () => _changeMonth(-1),
                          icon: const Icon(Icons.chevron_left),
                        ),
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            isExpanded: true,
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
                            isExpanded: true,
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
                                    DateFormat(
                                      'MMM',
                                    ).format(DateTime(2024, month)),
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
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 14),
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 7,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 1.0,
                  children: [
                    for (final day in weekdays)
                      Center(
                        child: Text(
                          _weekdayFormat.format(day).substring(0, 1),
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    for (final date in _calendarDays())
                      _DayCell(
                        date: date,
                        isToday: date != null && _isSameDay(date, today),
                        isSelected:
                            date != null &&
                            _selectedDate != null &&
                            _isSameDay(date, _selectedDate!),
                        onTap: date == null
                            ? null
                            : () {
                                setState(() => _selectedDate = date);
                              },
                      ),
                  ],
                ),
                const SizedBox(height: 18),
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
                    const SizedBox(width: 12),
                    FilledButton(
                      onPressed: _selectedDate == null
                          ? null
                          : () => Navigator.pop(context, _selectedDate),
                      child: const Text('Use Date'),
                    ),
                  ],
                ),
              ],
            ),
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
      borderRadius: BorderRadius.circular(10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: isSelected ? colorScheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isToday && !isSelected
                ? colorScheme.primary
                : Colors.transparent,
            width: 2,
          ),
        ),
        child: Center(
          child: Text(
            date!.day.toString(),
            style: theme.textTheme.bodyLarge?.copyWith(
              color: isSelected ? colorScheme.onPrimary : colorScheme.onSurface,
              fontWeight: isSelected || isToday
                  ? FontWeight.w700
                  : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

/// The phone picker: three wheels, the date and age spelled out above them,
/// and full-width buttons within thumb reach. Pops the chosen date, or
/// DateTime(1) for Clear, like [BirthdayPickerDialog].
class BirthdayWheelSheet extends StatefulWidget {
  const BirthdayWheelSheet({super.key, this.initialDate});

  final DateTime? initialDate;

  @override
  State<BirthdayWheelSheet> createState() => _BirthdayWheelSheetState();
}

class _BirthdayWheelSheetState extends State<BirthdayWheelSheet> {
  static const _itemExtent = 40.0;

  late final int _lastYear = DateTime.now().year;
  late int _year;
  late int _month;
  late int _day;
  late final FixedExtentScrollController _monthCtrl;
  late final FixedExtentScrollController _dayCtrl;
  late final FixedExtentScrollController _yearCtrl;

  @override
  void initState() {
    super.initState();
    final d = widget.initialDate ?? DateTime(2000);
    _year = d.year.clamp(1900, _lastYear);
    _month = d.month;
    _day = d.day;
    _monthCtrl = FixedExtentScrollController(initialItem: _month - 1);
    _dayCtrl = FixedExtentScrollController(initialItem: _day - 1);
    // Newest year first, as in the calendar's dropdown.
    _yearCtrl = FixedExtentScrollController(initialItem: _lastYear - _year);
  }

  @override
  void dispose() {
    _monthCtrl.dispose();
    _dayCtrl.dispose();
    _yearCtrl.dispose();
    super.dispose();
  }

  int get _daysInMonth => DateTime(_year, _month + 1, 0).day;

  DateTime get _date => DateTime(_year, _month, _day.clamp(1, _daysInMonth));

  /// 31 March becomes 30 April rather than 1 May.
  void _fitDay() {
    if (_day > _daysInMonth) {
      _day = _daysInMonth;
      _dayCtrl.jumpToItem(_day - 1);
    }
  }

  String get _age {
    final now = DateTime.now(), d = _date;
    var age = now.year - d.year;
    if (now.month < d.month || (now.month == d.month && now.day < d.day)) age--;
    if (d.isAfter(now)) return 'Not born yet';
    return age == 1 ? '1 year old' : '$age years old';
  }

  Widget _wheel({
    required FixedExtentScrollController controller,
    required int count,
    required String Function(int i) label,
    required ValueChanged<int> onSelected,
  }) {
    final theme = Theme.of(context);
    return CupertinoPicker.builder(
      scrollController: controller,
      itemExtent: _itemExtent,
      childCount: count,
      onSelectedItemChanged: onSelected,
      itemBuilder: (_, i) => Center(
        child: Text(
          label(i),
          style: theme.textTheme.titleMedium,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Birthday',
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, DateTime(1)),
                child: const Text('Clear'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${DateFormat('MMMM d, yyyy').format(_date)} · $_age',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: _itemExtent * 5,
            child: Row(
              children: [
                Expanded(
                  flex: 5,
                  child: _wheel(
                    controller: _monthCtrl,
                    count: 12,
                    label: (i) => DateFormat('MMMM').format(DateTime(2024, i + 1)),
                    onSelected: (i) => setState(() {
                      _month = i + 1;
                      _fitDay();
                    }),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: _wheel(
                    controller: _dayCtrl,
                    count: _daysInMonth,
                    label: (i) => '${i + 1}',
                    onSelected: (i) => setState(() => _day = i + 1),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: _wheel(
                    controller: _yearCtrl,
                    count: _lastYear - 1900 + 1,
                    label: (i) => '${_lastYear - i}',
                    onSelected: (i) => setState(() {
                      _year = _lastYear - i;
                      _fitDay();
                    }),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: () => Navigator.pop(context, _date),
            child: const Text('Use this date'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}
