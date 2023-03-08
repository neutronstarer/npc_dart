import 'dart:async';

import 'package:cancelable/cancelable.dart';
import 'package:npc/src/impl.dart';

/// [Handle] Method handle.
/// [param]  Param.
/// [cancelable] Cancel context.
typedef Handle = FutureOr<dynamic> Function(
  dynamic param,
  Cancelable cancelable,
  Notify notify,
);

/// [Notify] Notify.
/// [param]  Param.
typedef Notify = FutureOr<void> Function(
  dynamic param,
);

/// [Typ]
enum Typ {
  /// [emit] Emit.
  emit,

  /// [deliver] Deliver.

  deliver,

  /// [notify] Notify.

  notify,

  /// [ack] Ack.

  ack,

  /// [cancel] Cancel.
  cancel,
}

/// [Message] Message.
class Message {
  /// Create instance.
  Message({
    required this.typ,
    required this.id,
    this.method,
    this.param,
    this.error,
  });

  /// [typ] Typ.
  final Typ typ;

  /// [id] Id.

  final int id;

  /// [method] Method.

  final String? method;

  /// [param] Param.

  final dynamic param;

  /// [error] Error.

  final dynamic error;

  @override
  String toString() {
    final v = Map<String, dynamic>();
    v['typ'] = typ.index;
    v['id'] = id;
    if (method != null) {
      v['method'] = method;
    }
    if (param != null) {
      v['param'] = param.toString();
    }
    if (error != null) {
      v['error'] = error.toString();
    }
    return v.toString();
  }
}

/// [NPC] Near Procedure Call
abstract class NPC {
  factory NPC() {
    return NPCImpl();
  }

  /// Send message, must be set before work.
  late void Function(Message message) send;

  /// [receive] Receive message.
  /// [message] Message.
  Future<void> receive(Message message);

  /// [on] Register method handle.
  /// [method] Method name.
  /// [handle] Handle.
  void on(
    String method,
    Handle? handle,
  );

  Handle? operator [](String method);

  void operator []=(String method, Handle? value);

  /// [emit] Emit method without reply.
  /// [method] Method name.
  /// [param] Method param.
  void emit(
    String method, {
    dynamic param,
  });

  /// [deliver] Deliver method with reply.
  /// [method] Method name.
  /// [param] Method param.
  /// [timeout] Timeout.
  /// [cancelable] Cancel context.
  /// [onNotify] Called when notified.

  Future<dynamic> deliver(
    String method, {
    dynamic param,
    Duration? timeout,
    Cancelable? cancelable,
    Notify? onNotify,
  });

  /// [cleanUp] Clean up delivers with special reason, used when the connection is down.
  /// [reason] error.
  void cleanUp(dynamic reason);
}
