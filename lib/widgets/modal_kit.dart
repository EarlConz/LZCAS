// lib/widgets/modal_kit.dart
//
// One look for the staff forms (Edit/Add Product, Add/Edit Member) and
// destructive confirmations, from the "Staff Modals Redesign" canvas.
//
//   • AppModal          the frame. Desktop: a 18 px-radius dialog with a
//                       header (icon, title, subtitle, close), a scrolling
//                       body and a footer (note, Cancel, primary). Phone:
//                       full screen, close at top left, the primary button
//                       pinned full width at the bottom — Cancel is the X.
//                       Works inside showDialog and showAnimatedDialog.
//   • ModalSection      a titled group of fields
//   • FieldLabel        the label above a field (required marker)
//   • NumberStepper     − [n] + with a typed value and an error state
//   • SegmentedChoice   one-of-N, as a pill track
//   • ChoicePills       one-of-N, as wrapping pills (reasons)
//   • ModalNote         a tinted line of context (info / warn / danger)
//   • DangerZone        a red-outlined area for one destructive action
//   • confirmDestructive  the confirmation: dialog on desktop, bottom
//                       sheet on a phone
//
// Colours are the app's own (theme.dart) plus the darker caption and red
// the delivery screens already use for legible text.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:lzcas/theme.dart';
import 'package:lzcas/utils/fonts.dart';

/// Below this width a modal is a phone screen.
const double kModalCompactWidth = 600;

bool isCompactModal(BuildContext context) =>
    MediaQuery.sizeOf(context).width < kModalCompactWidth;

// Text colours that pass 4.5:1 on white; the theme's mutedText does not.
const Color _caption = Color(0xFF6E6E7A);
const Color _danger = Color(0xFFB91C1C);
const Color _orangeText = Color(0xFFB24800);

class _Palette {
  final bool dark;
  const _Palette(this.dark);
  Color get surface =>
      dark ? StockpileColors.darkSurface : StockpileColors.surface;
  Color get text =>
      dark ? StockpileColors.darkTextPrimary : StockpileColors.darkText;
  Color get body =>
      dark ? StockpileColors.darkTextBody : StockpileColors.bodyText;
  Color get muted => dark ? StockpileColors.darkTextMuted : _caption;
  Color get line =>
      dark ? StockpileColors.darkDivider : StockpileColors.divider;
  Color get field =>
      dark ? StockpileColors.darkInputBg : StockpileColors.inputBg;
  Color get track =>
      dark ? StockpileColors.darkInputBg : const Color(0xFFF0F0F4);
  static _Palette of(BuildContext c) =>
      _Palette(Theme.of(c).brightness == Brightness.dark);
}

// ─── The frame ──────────────────────────────────────────────────────────────

class AppModal extends StatelessWidget {
  final String title;
  final String? subtitle;

  /// Top-left of a desktop dialog: [ModalIconTile] or an avatar.
  final Widget? leading;

  /// The content, laid out top to bottom with [gap] between.
  final List<Widget> body;

  /// Footer text: a hint, a count of unsaved changes, an error.
  final Widget? footerNote;

  /// The main action. Full width on a phone.
  final Widget primaryAction;

  /// Desktop only; on a phone the close button at the top does this job.
  final String cancelLabel;

  final double maxWidth;
  final double gap;

  /// Called by close / Cancel. Defaults to popping the route.
  final VoidCallback? onClose;

  const AppModal({
    super.key,
    required this.title,
    required this.body,
    required this.primaryAction,
    this.subtitle,
    this.leading,
    this.footerNote,
    this.cancelLabel = 'Cancel',
    this.maxWidth = 560,
    this.gap = 22,
    this.onClose,
  });

  void _close(BuildContext context) =>
      onClose != null ? onClose!() : Navigator.of(context).maybePop();

  List<Widget> _spaced() => [
    for (var i = 0; i < body.length; i++) ...[
      if (i > 0) SizedBox(height: gap),
      body[i],
    ],
  ];

  @override
  Widget build(BuildContext context) {
    final p = _Palette.of(context);
    return isCompactModal(context) ? _phone(context, p) : _desktop(context, p);
  }

  Widget _titleBlock(_Palette p, {required bool compact}) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        title,
        style: StockpileFonts.satoshi(
          fontSize: compact ? 18 : 20,
          fontWeight: FontWeight.w700,
          color: p.text,
        ),
      ),
      if (subtitle != null) ...[
        const SizedBox(height: 2),
        Text(
          subtitle!,
          // The phone header is one 56 px bar: a second line would overflow it.
          maxLines: compact ? 1 : 2,
          overflow: TextOverflow.ellipsis,
          style: StockpileFonts.satoshi(
            fontSize: compact ? 12 : 13,
            color: p.muted,
          ),
        ),
      ],
    ],
  );

  Widget _closeButton(BuildContext context, _Palette p) => IconButton(
    tooltip: 'Close',
    onPressed: () => _close(context),
    icon: Icon(Icons.close_rounded, color: p.body),
    constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
  );

  Widget _desktop(BuildContext context, _Palette p) {
    final screen = MediaQuery.sizeOf(context);
    return Dialog(
      backgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 32),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxWidth,
          maxHeight: screen.height * 0.9,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 12, 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (leading != null) ...[leading!, const SizedBox(width: 14)],
                  Expanded(child: _titleBlock(p, compact: false)),
                  _closeButton(context, p),
                ],
              ),
            ),
            Divider(height: 1, color: p.line),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: _spaced(),
                ),
              ),
            ),
            Divider(height: 1, color: p.line),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 14, 24, 18),
              child: Row(
                children: [
                  Expanded(child: footerNote ?? const SizedBox.shrink()),
                  const SizedBox(width: 12),
                  TextButton(
                    onPressed: () => _close(context),
                    child: Text(cancelLabel),
                  ),
                  const SizedBox(width: 8),
                  primaryAction,
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _phone(BuildContext context, _Palette p) {
    return Dialog.fullscreen(
      backgroundColor: p.surface,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 56,
              child: Row(
                children: [
                  const SizedBox(width: 4),
                  _closeButton(context, p),
                  const SizedBox(width: 4),
                  Expanded(child: _titleBlock(p, compact: true)),
                  const SizedBox(width: 12),
                ],
              ),
            ),
            Divider(height: 1, color: p.line),
            Expanded(
              child: SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: _spaced(),
                ),
              ),
            ),
            Divider(height: 1, color: p.line),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (footerNote != null) ...[
                    Center(child: footerNote!),
                    const SizedBox(height: 8),
                  ],
                  SizedBox(width: double.infinity, child: primaryAction),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The 44 px tinted square in a desktop header.
class ModalIconTile extends StatelessWidget {
  final IconData icon;
  final ModalTone tone;
  const ModalIconTile(this.icon, {super.key, this.tone = ModalTone.warn});

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = tone.colors(
      Theme.of(context).brightness == Brightness.dark,
    );
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, size: 22, color: fg),
    );
  }
}

// ─── Fields ─────────────────────────────────────────────────────────────────

class ModalSection extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const ModalSection({super.key, required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final p = _Palette.of(context);
    return Semantics(
      container: true,
      label: title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: StockpileFonts.satoshi(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: p.body,
            ),
          ),
          for (final c in children) ...[const SizedBox(height: 12), c],
        ],
      ),
    );
  }
}

class FieldLabel extends StatelessWidget {
  final String text;
  final bool required;
  final String? aside;
  const FieldLabel(this.text, {super.key, this.required = false, this.aside});

  @override
  Widget build(BuildContext context) {
    final p = _Palette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text.rich(
        TextSpan(
          text: text,
          style: StockpileFonts.satoshi(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: p.text,
          ),
          children: [
            if (required)
              TextSpan(
                text: ' *',
                style: StockpileFonts.satoshi(fontSize: 13, color: _danger),
              ),
            if (aside != null)
              TextSpan(
                text: '  ·  $aside',
                style: StockpileFonts.satoshi(
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  color: p.muted,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A label above any field.
class LabeledField extends StatelessWidget {
  final String label;
  final bool required;
  final String? aside;
  final Widget child;
  const LabeledField({
    super.key,
    required this.label,
    required this.child,
    this.required = false,
    this.aside,
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      FieldLabel(label, required: required, aside: aside),
      child,
    ],
  );
}

/// Two fields side by side on desktop, stacked on a phone. [keepPaired]
/// keeps short pairs (Middle name / Birthday) side by side on a phone too.
class FieldPair extends StatelessWidget {
  final Widget first;
  final Widget second;
  final bool keepPaired;
  const FieldPair(
    this.first,
    this.second, {
    super.key,
    this.keepPaired = false,
  });

  @override
  Widget build(BuildContext context) {
    if (isCompactModal(context) && !keepPaired) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [first, const SizedBox(height: 12), second],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: first),
        SizedBox(width: isCompactModal(context) ? 10 : 14),
        Expanded(child: second),
      ],
    );
  }
}

/// − [n] + : typed or stepped. [errorText] outlines it red and shows the
/// message underneath; [helperText] shows when there is no error.
class NumberStepper extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final int min;
  final int? max;
  final String? errorText;
  final String? helperText;
  final String semanticLabel;
  final bool enabled;
  final bool expand;

  const NumberStepper({
    super.key,
    required this.controller,
    required this.onChanged,
    required this.semanticLabel,
    this.min = 0,
    this.max,
    this.errorText,
    this.helperText,
    this.enabled = true,
    this.expand = false,
  });

  void _step(int delta) {
    final now = int.tryParse(controller.text.trim()) ?? 0;
    var next = now + delta;
    if (next < min) next = min;
    // Stepping never goes past the limit; typing can, and then the error
    // explains why.
    if (max != null && delta > 0 && next > max!) next = max! < min ? min : max!;
    controller.text = '$next';
    onChanged(controller.text);
  }

  @override
  Widget build(BuildContext context) {
    final p = _Palette.of(context);
    final hasError = errorText != null;
    final compact = isCompactModal(context);
    final btnW = compact ? 52.0 : 44.0;

    Widget stepButton(IconData icon, String label, int delta) => SizedBox(
      width: btnW,
      height: 46,
      child: IconButton(
        tooltip: label,
        onPressed: enabled ? () => _step(delta) : null,
        icon: Icon(icon, size: 18, color: p.text),
      ),
    );

    final field = Container(
      height: 48,
      decoration: BoxDecoration(
        color: hasError
            ? (p.dark ? _danger.withAlpha(30) : const Color(0xFFFEF2F2))
            : p.field,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: hasError ? _danger : p.line,
          width: hasError ? 2 : 1,
        ),
      ),
      child: Row(
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        children: [
          stepButton(Icons.remove_rounded, 'One less', -1),
          SizedBox(width: expand ? null : 64, child: expand ? null : _input(p)),
          if (expand) Expanded(child: _input(p)),
          stepButton(Icons.add_rounded, 'One more', 1),
        ],
      ),
    );

    final under = errorText ?? helperText;
    // A fixed width unless [expand]: placed in a Row (beside a preview) it
    // would otherwise get unbounded width, and the Flexible message below
    // throws as soon as an error appears.
    return SizedBox(
      // + 4: the border (2 px a side when it shows an error) sits inside
      // this width, and the buttons and input need their full 2 × btnW + 64.
      width: expand ? null : btnW * 2 + 64 + 4,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          field,
          if (under != null) ...[
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (hasError) ...[
                  const Icon(
                    Icons.error_outline_rounded,
                    size: 15,
                    color: _danger,
                  ),
                  const SizedBox(width: 6),
                ],
                Flexible(
                  child: Text(
                    under,
                    style: StockpileFonts.satoshi(
                      fontSize: 12,
                      fontWeight: hasError ? FontWeight.w600 : FontWeight.w400,
                      color: hasError ? _danger : p.muted,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _input(_Palette p) => Semantics(
    label: semanticLabel,
    child: TextField(
      controller: controller,
      enabled: enabled,
      onChanged: onChanged,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      textAlign: TextAlign.center,
      style: StockpileFonts.satoshi(
        fontSize: 17,
        fontWeight: FontWeight.w700,
        color: p.text,
      ),
      decoration: const InputDecoration(
        isDense: true,
        filled: false,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        contentPadding: EdgeInsets.symmetric(vertical: 12),
      ),
    ),
  );
}

/// One-of-N as a pill track: "No change | Add | Reduce".
class SegmentedChoice<T> extends StatelessWidget {
  final List<(T, String)> options;
  final T value;
  final ValueChanged<T> onChanged;
  const SegmentedChoice({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final p = _Palette.of(context);
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: p.track,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          for (final (v, label) in options)
            Expanded(
              child: Semantics(
                inMutuallyExclusiveGroup: true,
                selected: v == value,
                button: true,
                child: Material(
                  color: v == value ? p.surface : Colors.transparent,
                  elevation: v == value ? 1 : 0,
                  borderRadius: BorderRadius.circular(10),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => onChanged(v),
                    child: SizedBox(
                      height: 40,
                      child: Center(
                        child: Text(
                          label,
                          style: StockpileFonts.satoshi(
                            fontSize: 14,
                            fontWeight: v == value
                                ? FontWeight.w700
                                : FontWeight.w400,
                            color: v == value ? p.text : p.body,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// One-of-N as wrapping pills: the reason for a stock reduction.
class ChoicePills extends StatelessWidget {
  final List<String> options;
  final String? value;
  final ValueChanged<String> onChanged;
  const ChoicePills({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final p = _Palette.of(context);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final o in options)
          Semantics(
            inMutuallyExclusiveGroup: true,
            selected: o == value,
            button: true,
            child: Material(
              color: o == value
                  ? (p.dark
                        ? StockpileColors.primary900.withAlpha(30)
                        : StockpileColors.primary50)
                  : p.surface,
              shape: StadiumBorder(
                side: BorderSide(
                  color: o == value ? StockpileColors.primary900 : p.line,
                  width: o == value ? 1.5 : 1,
                ),
              ),
              child: InkWell(
                customBorder: const StadiumBorder(),
                onTap: () => onChanged(o),
                child: Container(
                  height: 40,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  alignment: Alignment.center,
                  child: Text(
                    o,
                    style: StockpileFonts.satoshi(
                      fontSize: 14,
                      fontWeight: o == value
                          ? FontWeight.w600
                          : FontWeight.w400,
                      color: o == value
                          ? (p.dark ? StockpileColors.primary500 : _orangeText)
                          : p.text,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ─── Notes ──────────────────────────────────────────────────────────────────

enum ModalTone {
  info,
  warn,
  danger,
  neutral;

  (Color bg, Color fg) colors(bool dark) => switch (this) {
    ModalTone.info => (
      dark
          ? StockpileColors.secondary500.withAlpha(40)
          : StockpileColors.secondary50,
      dark ? StockpileColors.secondary200 : StockpileColors.secondary600,
    ),
    ModalTone.warn => (
      dark
          ? StockpileColors.primary900.withAlpha(30)
          : StockpileColors.primary50,
      dark ? StockpileColors.primary500 : _orangeText,
    ),
    ModalTone.danger => (
      dark ? _danger.withAlpha(40) : StockpileColors.dangerBg,
      dark ? const Color(0xFFFCA5A5) : _danger,
    ),
    ModalTone.neutral => (
      dark ? StockpileColors.darkInputBg : StockpileColors.inputBg,
      dark ? StockpileColors.darkTextBody : StockpileColors.bodyText,
    ),
  };
}

class ModalNote extends StatelessWidget {
  final IconData icon;
  final ModalTone tone;
  final String? title;
  final String body;
  const ModalNote({
    super.key,
    required this.body,
    this.title,
    this.icon = Icons.info_outline_rounded,
    this.tone = ModalTone.neutral,
  });

  @override
  Widget build(BuildContext context) {
    final p = _Palette.of(context);
    final (bg, fg) = tone.colors(p.dark);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 18, color: fg),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  if (title != null)
                    TextSpan(
                      text: '$title ',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  TextSpan(text: body),
                ],
              ),
              style: StockpileFonts.satoshi(
                fontSize: 13,
                color: p.text,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A red-outlined area for one destructive action, kept apart from Save.
class DangerZone extends StatelessWidget {
  final String title;
  final String body;
  final String actionLabel;
  final VoidCallback? onPressed;
  const DangerZone({
    super.key,
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final p = _Palette.of(context);
    final compact = isCompactModal(context);
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: StockpileFonts.satoshi(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: _danger,
          ),
        ),
        const SizedBox(height: 2),
        Text(body, style: StockpileFonts.satoshi(fontSize: 13, color: p.body)),
      ],
    );
    final button = OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: _danger,
        side: const BorderSide(color: _danger),
        minimumSize: const Size(0, 44),
      ),
      child: Text(actionLabel),
    );
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: p.dark ? _danger.withAlpha(120) : const Color(0xFFF5B4B4),
        ),
      ),
      child: compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [text, const SizedBox(height: 10), button],
            )
          : Row(
              children: [
                Expanded(child: text),
                const SizedBox(width: 16),
                button,
              ],
            ),
    );
  }
}

// ─── Confirmation ───────────────────────────────────────────────────────────

/// Ask before something that can't be undone. A dialog on desktop, a sheet
/// from the bottom on a phone. Resolves true only on the confirm button.
///
/// Name the buttons for what they do ("Delete product", "Keep it"), never
/// Yes / No: the reader should not have to reread the question.
Future<bool> confirmDestructive(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  String cancelLabel = 'Keep it',
  String? detail,
  IconData icon = Icons.delete_outline_rounded,
}) async {
  Widget content(BuildContext ctx, {required bool sheet}) {
    final p = _Palette.of(ctx);
    final (bg, fg) = ModalTone.danger.colors(p.dark);
    final confirm = FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: _danger,
        foregroundColor: Colors.white,
      ),
      onPressed: () => Navigator.of(ctx).pop(true),
      child: Text(confirmLabel),
    );
    final cancel = OutlinedButton(
      onPressed: () => Navigator.of(ctx).pop(false),
      child: Text(cancelLabel),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
              child: Icon(icon, size: 22, color: fg),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: StockpileFonts.satoshi(
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                      color: p.text,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    message,
                    style: StockpileFonts.satoshi(
                      fontSize: 14,
                      color: p.body,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (detail != null) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: p.field,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              detail,
              style: StockpileFonts.satoshi(fontSize: 14, color: p.text),
            ),
          ),
        ],
        const SizedBox(height: 20),
        if (sheet) ...[
          confirm,
          const SizedBox(height: 10),
          cancel,
        ] else
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [cancel, const SizedBox(width: 10), confirm],
          ),
      ],
    );
  }

  final bool? ok;
  if (isCompactModal(context)) {
    ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: _Palette.of(context).surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: content(ctx, sheet: true),
        ),
      ),
    );
  } else {
    ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: _Palette.of(ctx).surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: content(ctx, sheet: false),
          ),
        ),
      ),
    );
  }
  return ok ?? false;
}
