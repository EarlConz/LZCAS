import 'package:flutter/material.dart';

class SettingsPage extends StatefulWidget {
  final ValueChanged<bool>? onToggle;
  final bool initialDark;

  const SettingsPage({super.key, this.onToggle, this.initialDark = false});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late bool _dark;

  void _onToggle(bool val) {
    setState(() => _dark = val);
    widget.onToggle?.call(_dark);
  }

  @override
  void initState() {
    super.initState();
    _dark = widget.initialDark;
  }

  @override
  void didUpdateWidget(covariant SettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialDark != widget.initialDark) {
      setState(() {
        _dark = widget.initialDark;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          const SizedBox(height: 20),
          Row(
            children: [
              const Expanded(child: Text('Dark mode')),
              Switch(value: _dark, onChanged: _onToggle),
            ],
          ),
        ],
      ),
    );
  }
}
