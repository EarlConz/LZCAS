// lib/services/delivery_notification_service.dart
// Realtime toast + audible chime for delivery orders.
//
// Subscribes to the parsed `orders` realtime stream and tells each party
// about the moments they have to act on, or would otherwise miss:
//   * Cashier / Admin  — a new order; the member countered the fee; the
//                        member agreed (ready to dispatch); an order was
//                        cancelled while a rider had it (goods come back).
//   * Member / Reseller — prices quoted; counter-offer accepted; a rider
//                        assigned; on the way; delivered (please confirm);
//                        cancelled (with the refund, if any).
//   * Rider            — an order assigned to them; one of theirs
//                        cancelled or completed.
//
// Only on a CHANGE of status. An order row is also updated for its route,
// payment, ETA and cash code, and each of those arrives as an 'updated'
// event carrying the same status; toasting on status alone chimed again
// for every one. Realtime sends no previous row, so the service remembers
// the last status it saw per order, seeded from one fetch at sign-in.
//
// In-app only: nothing reaches a phone whose app is closed. That would
// need push notifications (FCM), which the app does not have.
//
// Branch Cashiers are deliberately NOT a listener — delivery orders are
// the main cashier's and the admin's (v55).

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

  /// Last status seen per order id: the "before" half of each transition.
  final Map<String, String> _lastStatus = {};

  /// Who the seed was taken for, so signing in as someone else re-seeds.
  String? _seededFor;

  /// Attach the service to the authenticated user and the realtime stream.
  /// Safe to call once; subsequent calls are no-ops.
  void start(AuthState auth) {
    if (_started) return;
    _started = true;
    _auth = auth;
    _resolveMemberId();
    _seed();
    _sub = repository.orderEvents.listen(_onOrderEvent);
    // Re-resolve the member id once the user actually signs in (the service
    // is constructed at boot, before the session is restored).
    auth.addListener(_onAuthChanged);
  }

  void _onAuthChanged() {
    final auth = _auth;
    if (auth == null) return;
    if (_isMember && _myMemberId == null) _resolveMemberId();
    if (auth.userId != _seededFor) _seed();
  }

  Future<void> _resolveMemberId() async {
    try {
      final member = await repository.fetchMyMember();
      _myMemberId = member?.id;
    } catch (_) {}
  }

  /// Remember the status of every order this account can see right now, so
  /// the first update to each is compared with something. RLS scopes the
  /// fetch to the caller's own orders.
  Future<void> _seed() async {
    final uid = _auth?.userId;
    _seededFor = uid;
    _lastStatus.clear();
    if (uid == null || !(_isStaff || _isMember || _isRider)) return;
    try {
      final orders = await repository.fetchDeliveryOrders();
      for (final o in orders) {
        _lastStatus.putIfAbsent(o.id, () => o.status);
      }
    } catch (_) {}
  }

  bool get _isStaff =>
      _auth?.userRole == UserRole.cashier || _auth?.userRole == UserRole.admin;

  bool get _isMember =>
      _auth?.userRole == UserRole.member ||
      _auth?.userRole == UserRole.reseller;

  bool get _isRider => _auth?.userRole == UserRole.delivery;

  void _onOrderEvent(DeliveryOrderRealtimeEvent event) {
    final order = event.order;
    if (order.id.isEmpty || event.type == 'deleted') return;

    final before = _lastStatus[order.id];
    _lastStatus[order.id] = order.status;
    // Same status as last time: a route, payment or ETA write. Nothing new
    // for anyone to act on.
    if (before == order.status) return;

    final ref = 'Order ${order.shortId}';
    if (_isStaff) {
      _forStaff(event, order, before, ref);
    } else if (_isMember) {
      // Ignore other members' orders, should any arrive.
      if (_myMemberId == null || order.memberId != _myMemberId) return;
      _forMember(order, before);
    } else if (_isRider) {
      if (order.deliveryId != _auth?.userId) return;
      _forRider(order, ref);
    }
  }

  void _forStaff(
    DeliveryOrderRealtimeEvent event,
    DeliveryOrder order,
    String? before,
    String ref,
  ) {
    // A cashier hears about the orders they hold and the ones nobody has
    // picked up yet; an admin, about all of them.
    final mine =
        _auth?.userRole == UserRole.admin ||
        order.cashierId == null ||
        order.cashierId == _auth?.userId;
    if (!mine) return;

    final onTheRoad =
        before == DeliveryOrderStatus.assigned ||
        before == DeliveryOrderStatus.pickedUp ||
        before == DeliveryOrderStatus.delivered;

    if (event.type == 'added' &&
        order.status == DeliveryOrderStatus.orderPlaced) {
      _notify('New delivery order', 'A member just placed an order.');
    } else if (order.status == DeliveryOrderStatus.memberNegotiating) {
      _notify('Delivery counter-offer', '$ref: the member countered the fee.');
    } else if (order.status == DeliveryOrderStatus.agreed &&
        before == DeliveryOrderStatus.cashierPricing) {
      _notify('Ready to dispatch', '$ref: the member agreed to the price.');
    } else if (order.status == DeliveryOrderStatus.cancelled && onTheRoad) {
      final why = (order.cancelReason ?? '').trim();
      _notify(
        'Delivery cancelled',
        '$ref was cancelled while with the rider'
            '${why.isEmpty ? '' : ' ($why)'}. The goods come back to the store.',
      );
    }
  }

  void _forMember(DeliveryOrder order, String? before) {
    final status = order.status;
    if (status == DeliveryOrderStatus.cashierPricing) {
      _notify(
        'Order priced',
        'The cashier sent your item prices and delivery quote.',
      );
    } else if (status == DeliveryOrderStatus.agreed &&
        before == DeliveryOrderStatus.memberNegotiating) {
      _notify(
        'Delivery fee accepted',
        'The cashier accepted your offer. Choose how to pay in Active Orders.',
      );
    } else if (status == DeliveryOrderStatus.assigned) {
      _notify(
        'Rider assigned',
        '${order.deliveryName ?? 'A rider'} will bring your order.',
      );
    } else if (status == DeliveryOrderStatus.pickedUp) {
      _notify('On the way', 'Your order has left the store.');
    } else if (status == DeliveryOrderStatus.delivered) {
      _notify(
        'Delivered',
        'Your order was handed over. Tap "Yes, I received it" in Active Orders.',
      );
    } else if (status == DeliveryOrderStatus.cancelled) {
      final why = (order.cancelReason ?? '').trim();
      _notify(
        'Order cancelled',
        '${why.isEmpty ? 'Your order was cancelled.' : 'Your order was cancelled: $why.'}'
            '${order.isRefunded ? ' Your payment was returned to your funds.' : ''}',
      );
    }
  }

  void _forRider(DeliveryOrder order, String ref) {
    final status = order.status;
    if (status == DeliveryOrderStatus.assigned) {
      _notify('New delivery', '$ref was assigned to you.');
    } else if (status == DeliveryOrderStatus.cancelled) {
      _notify('Delivery cancelled', '$ref was cancelled.');
    } else if (status == DeliveryOrderStatus.completed) {
      _notify('Delivery complete', '$ref is done.');
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
