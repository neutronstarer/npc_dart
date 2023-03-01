import 'dart:async';

import 'package:cancelable/cancelable.dart';
import 'package:npc/src/impl.dart';
import 'message.dart';

/// [NPC] Near Procedure Call
abstract class NPC {
  factory NPC() {
    return NPCImpl();
  }

  /// Send message, must be set before work.
  late Future<void> Function(Message message) send;

  /// [receive] Receive message.
  /// [message] Message.
  Future<void> receive(Message message);

  /// [on] Register method handle.
  /// [method] Method name.
  /// [handle] Handle.
  void on(
    String method,
    Handle handle,
  );

  /// [emit] Emit method without reply.
  /// [method] Method name.
  /// [param] Method param.
  Future<void> emit(
    String method, {
    dynamic param,
  });

  /// [deliver] Deliver method with reply.
  /// [method] Method name.
  /// [param] Method param.
  /// [timeout] Timeout.
  /// [cancelable] Cancel context.
  /// [onNotify] Called when notified.

  Future deliver(
    String method, {
    dynamic param,
    Duration? timeout,
    Cancelable? cancelable,
    Notify? onNotify,
  });

  /// [cleanUpDeliveries] Clean up all deliveries with special reason.
  /// [reason] error.
  Future<void> cleanUpDeliveries(dynamic reason);
}
