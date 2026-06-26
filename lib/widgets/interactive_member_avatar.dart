import 'package:flutter/material.dart';
import 'package:lzcas/utils/animations.dart';
import 'memberqr.dart';

class InteractiveMemberAvatar extends StatefulWidget {
  final int? memberId;
  final String lastName;
  final String firstName;
  final String middleName;
  final String contactNo;
  final String birthday;
  final String address;
  final String referrer;
  final String? imageUrl; // optional member image path or network url
  final double size;
  final String? qrToken;

  const InteractiveMemberAvatar({
    super.key,
    this.memberId,
    required this.lastName,
    required this.firstName,
    required this.middleName,
    this.contactNo = '',
    this.birthday = '',
    this.address = '',
    this.referrer = '',
    this.imageUrl,
    this.size = 56,
    this.qrToken,
  });

  @override
  State<InteractiveMemberAvatar> createState() =>
      _InteractiveMemberAvatarState();
}

class _InteractiveMemberAvatarState extends State<InteractiveMemberAvatar> {
  bool _hovering = false;

  void _showQrDialog() {
    showAnimatedDialog(
      context,
      builder: (ctx) {
        final dialogTheme = Theme.of(ctx).dialogTheme;
        return Dialog(
          backgroundColor:
              dialogTheme.backgroundColor ?? Theme.of(ctx).cardColor,
          shape:
              dialogTheme.shape ??
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                MemberQrWithName(
                  lastName: widget.lastName,
                  firstName: widget.firstName,
                  middleName: widget.middleName,
                  contactNo: widget.contactNo,
                  birthday: widget.birthday,
                  address: widget.address,
                  referrer: widget.referrer,
                  qrToken: widget.qrToken,
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Close'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final avatar = widget.imageUrl != null && widget.imageUrl!.isNotEmpty
        ? CircleAvatar(
            radius: widget.size / 2,
            backgroundImage: AssetImage(widget.imageUrl!),
          )
        : CircleAvatar(
            radius: widget.size / 2,
            child: Text(
              '${widget.firstName.isNotEmpty ? widget.firstName[0] : ''}${widget.lastName.isNotEmpty ? widget.lastName[0] : ''}'
                  .toUpperCase(),
            ),
          );

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: _showQrDialog,
        child: Stack(
          alignment: Alignment.center,
          children: [
            avatar,
            // Hover QR appears inside the avatar circle (centered) and slightly smaller than the avatar to fit.
            Positioned.fill(
              child: Center(
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 160),
                  opacity: _hovering ? 1.0 : 0.0,
                  child: ClipOval(
                    child: Container(
                      width: widget.size,
                      height: widget.size,
                      color: Theme.of(context).cardColor,
                      alignment: Alignment.center,
                      child: SizedBox(
                        width: widget.size * 0.9,
                        height: widget.size * 0.9,
                        child: MemberQr(
                          lastName: widget.lastName,
                          firstName: widget.firstName,
                          middleName: widget.middleName,
                          contactNo: widget.contactNo,
                          birthday: widget.birthday,
                          address: widget.address,
                          referrer: widget.referrer,
                          qrToken: widget.qrToken,
                          size: widget.size * 0.9,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
