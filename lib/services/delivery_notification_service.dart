// lib/services/delivery_notification_service.dart
// Realtime toast + audible chime for the Member Ordering & Delivery
// Negotiation workflow (v48).
//
// Subscribes to the parsed `orders` realtime stream and notifies the right
// party on the right transition:
//   * Cashier / Admin  — new order ('Order Placed') or a member counter
//                        ('Member Negotiating').
//   * Member / Reseller — cashier finished pricing & quoted
//                        ('Cashier Pricing & Negotiating').
//
// Branch Cashiers are deliberately NOT a listener — the feature is
// Cashier/Admin only.

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show SystemSound, SystemSoundType;
import 'package:bot_toast/bot_toast.dart';
import '../auth/auth.dart';
import '../db/db.dart';

class DeliveryNotificationService extends ChangeNotifier {
  StreamSubscription<DeliveryOrderRealtimeEvent>? _sub;
  AuthState? _auth;
  int? _myMemberId;
  bool _started = false;

  /// Attach the service to the authenticated user and the realtime stream.
  /// Safe to call once; subsequent calls are no-ops.
  void start(AuthState auth) {
    if (_started) return;
    _started = true;
    _auth = auth;
    _resolveMemberId();
    _sub = repository.orderEvents.listen(_onOrderEvent);
    // Re-resolve the member id once the user actually signs in (the service
    // is constructed at boot, before the session is restored).
    auth.addListener(_onAuthChanged);
  }

  void _onAuthChanged() {
    final auth = _auth;
    if (auth == null) return;
    if (_isMember && _myMemberId == null) _resolveMemberId();
  }

  Future<void> _resolveMemberId() async {
    try {
      final member = await repository.fetchMyMember();
      _myMemberId = member?.id;
    } catch (_) {}
  }

  bool get _isStaff =>
      _auth?.userRole == UserRole.cashier || _auth?.userRole == UserRole.admin;

  bool get _isMember =>
      _auth?.userRole == UserRole.member ||
      _auth?.userRole == UserRole.reseller;

  void _onOrderEvent(DeliveryOrderRealtimeEvent event) {
    final order = event.order;
    if (order.id.isEmpty) return;

    if (_isStaff) {
      if (event.type == 'added' &&
          order.status == DeliveryOrderStatus.orderPlaced) {
        _notify('New delivery order', 'A member just placed an order.');
        return;
      }
      if (event.type == 'updated' &&
          order.status == DeliveryOrderStatus.memberNegotiating) {
        _notify(
          'Delivery counter-offer',
          'A member countered the delivery fee.',
        );
        return;
      }
      return;
    }

    if (_isMember) {
      // Ignore other members' orders — the stream is unfiltered.
      if (_myMemberId == null || order.memberId != _myMemberId) return;
      if (event.type == 'updated' &&
          order.status == DeliveryOrderStatus.cashierPricing) {
        _notify(
          'Order priced',
          'The cashier sent your item prices and delivery quote.',
        );
        return;
      }
      return;
    }
  }

  void _notify(String title, String message) {
    BotToast.showText(text: '$title: $message');
    // Audible chime — a no-op on platforms without system sounds.
    try {
      SystemSound.play(SystemSoundType.alert);
    } catch (_) {}
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
