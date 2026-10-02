// lib/services/delivery_notification_service.dart
// Realtime toast + audible chime for delivery orders.
//
// Subscribes to the parsed `orders` realtime stream and tells each party
// about the moments they have to act on, or would otherwise miss:
//   * Cashier / Admin  — a new order; the member countered the fee; the
//                        member agreed (ready to dispatch); an order was
//                        cancelled while a rider had it (goods come back).
//                        Courier orders (v61): the member says they sent
//                        an outside payment; the order is paid and ready
//                        to ship.
//   * Member / Reseller — prices quoted; counter-offer accepted; a rider
//                        assigned; on the way; delivered (please confirm);
//                        cancelled (with the refund, if any). Courier
//                        orders: where to pay; payment not received;
//                        payment confirmed; shipped.
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

  /// Whether each order was ready for a rider when last seen (v59: agreed
  /// AND paid or cash chosen). Paying changes no status, so this is how
  /// the cashier's "Ready to dispatch" knows the moment it happens.
  final Map<String, bool> _lastReady = {};

  /// The order as last seen, for the outside-payment steps (v61), which
  /// change no status either.
  final Map<String, DeliveryOrder> _lastOrder = {};

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
    _lastReady.clear();
    _lastOrder.clear();
    if (uid == null || !(_isStaff || _isMember || _isRider)) return;
    try {
      final orders = await repository.fetchDeliveryOrders();
      for (final o in orders) {
        _lastStatus.putIfAbsent(o.id, () => o.status);
        _lastReady.putIfAbsent(o.id, () => _ready(o));
        _lastOrder.putIfAbsent(o.id, () => o);
      }
    } catch (_) {}
  }

  bool get _isStaff =>
      _auth?.userRole == UserRole.cashier || _auth?.userRole == UserRole.admin;

  bool get _isMember =>
      _auth?.userRole == UserRole.member ||
      _auth?.userRole == UserRole.reseller;

  bool get _isRider => _auth?.userRole == UserRole.delivery;

  /// Ready for the staff's next step: a rider (v59) or the courier (v61).
  static bool _ready(DeliveryOrder o) => o.readyForRider || o.readyToShip;

  /// Which outside-payment step [order] just took since [prev], if any.
  static String? _paymentStep(DeliveryOrder? prev, DeliveryOrder order) {
    if (prev == null) return null;
    if (order.paymentDetailsAt != null &&
        order.paymentDetailsAt != prev.paymentDetailsAt) {
      return 'details';
    }
    if (order.paymentSentAt != null &&
        order.paymentSentAt != prev.paymentSentAt) {
      return 'sent';
    }
    if (order.paymentRejectedAt != null &&
        order.paymentRejectedAt != prev.paymentRejectedAt) {
      return 'rejected';
    }
    if (order.isOutside && order.isPaid && !prev.isPaid) return 'confirmed';
    return null;
  }

  void _onOrderEvent(DeliveryOrderRealtimeEvent event) {
    final order = event.order;
    if (order.id.isEmpty || event.type == 'deleted') return;

    final before = _lastStatus[order.id];
    final wasReady = _lastReady[order.id] ?? false;
    final step = _paymentStep(_lastOrder[order.id], order);
    _lastStatus[order.id] = order.status;
    _lastReady[order.id] = _ready(order);
    _lastOrder[order.id] = order;
    final statusChanged = before != order.status;
    final becameReady = _ready(order) && !wasReady;
    // Nothing moved: a route, ETA or cash-code write. Nothing new for
    // anyone to act on.
    if (!statusChanged && !becameReady && step == null) return;

    final ref = 'Order ${order.shortId}';
    if (_isStaff) {
      _forStaff(event, order, before, ref, statusChanged, becameReady, step);
    } else if (_isMember) {
      // Ignore other members' orders, should any arrive.
      if (!statusChanged && step == null) return;
      if (_myMemberId == null || order.memberId != _myMemberId) return;
      _forMember(order, before, statusChanged, step);
    } else if (_isRider) {
      if (!statusChanged) return;
      if (order.deliveryId != _auth?.userId) return;
      _forRider(order, ref);
    }
  }

  void _forStaff(
    DeliveryOrderRealtimeEvent event,
    DeliveryOrder order,
    String? before,
    String ref,
    bool statusChanged,
    bool becameReady,
    String? step,
  ) {
    // A cashier hears about the orders they hold and the ones nobody has
    // picked up yet. An admin hears about every new order and every
    // completed one, and the rest only while no cashier holds the order
    // (client decision 2026-10-03: admins were getting too many alerts).
    final isAdmin = _auth?.userRole == UserRole.admin;
    if (isAdmin &&
        statusChanged &&
        order.status == DeliveryOrderStatus.completed) {
      // Not for the admin who closed it themselves.
      if (order.confirmedBy != _auth?.userId) {
        _notify('Order completed', '$ref is complete.');
      }
      return;
    }
    final isNew =
        event.type == 'added' && order.status == DeliveryOrderStatus.orderPlaced;
    final mine = isAdmin
        ? (isNew || order.cashierId == null)
        : (order.cashierId == null || order.cashierId == _auth?.userId);
    if (!mine) return;

    final onTheRoad =
        before == DeliveryOrderStatus.assigned ||
        before == DeliveryOrderStatus.pickedUp ||
        before == DeliveryOrderStatus.delivered;

    if (event.type == 'added' &&
        order.status == DeliveryOrderStatus.orderPlaced) {
      _notify('New delivery order', 'A member just placed an order.');
    } else if (statusChanged &&
        order.status == DeliveryOrderStatus.memberNegotiating) {
      _notify('Delivery counter-offer', '$ref: the member countered the fee.');
    } else if (step == 'sent') {
      _notify(
        'Payment sent',
        '$ref: the member says they sent the payment. Check it arrived, '
            'then confirm it.',
      );
    } else if (becameReady && order.isCourier) {
      // Confirming an outside payment is the staff's own act: no alert.
      if (step != 'confirmed') {
        _notify(
          'Ready to ship',
          '$ref: paid. Book it with ${order.routeLabel} and mark it shipped.',
        );
      }
    } else if (becameReady) {
      // v59: ready for a rider once agreed AND paid or cash chosen,
      // whichever came last.
      _notify(
        'Ready to dispatch',
        order.isPaid
            ? "$ref: paid from the member's funds."
            : '$ref: the member will pay cash on delivery.',
      );
    } else if (statusChanged &&
        order.status == DeliveryOrderStatus.cancelled &&
        onTheRoad) {
      final why = (order.cancelReason ?? '').trim();
      _notify(
        'Delivery cancelled',
        '$ref was cancelled while with the rider'
            '${why.isEmpty ? '' : ' ($why)'}. The goods come back to the store.',
      );
    }
  }

  void _forMember(
    DeliveryOrder order,
    String? before,
    bool statusChanged,
    String? step,
  ) {
    if (!statusChanged) {
      if (step == 'details') {
        _notify(
          'Where to pay',
          'The store sent where to send your payment. See it in Active Orders.',
        );
      } else if (step == 'rejected') {
        final why = (order.paymentRejectedNote ?? '').trim();
        _notify(
          'Payment not received',
          why.isEmpty
              ? 'The store could not confirm your payment.'
              : 'The store could not confirm your payment: $why',
        );
      } else if (step == 'confirmed') {
        _notify(
          'Payment confirmed',
          'The store received your payment. They will send your order by '
              '${order.routeLabel}.',
        );
      }
      return;
    }
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
    } else if (status == DeliveryOrderStatus.shipped) {
      final tracking = (order.trackingNumber ?? '').trim();
      _notify(
        'Shipped',
        'Your order was sent by ${order.routeLabel}'
            '${tracking.isEmpty ? '' : ' (tracking $tracking)'}. Tap "I '
            'received it" in Active Orders when it arrives.',
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
