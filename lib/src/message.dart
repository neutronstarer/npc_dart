import 'package:cancelable/cancelable.dart';

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
    this.id,
    this.method,
    this.param,
    this.error,
  });

  /// [typ] Typ.
  final Typ typ;

  /// [id] Id.

  final int? id;

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
    v['typ_s'] = typ.toString();
    if (id != null) {
      v['id'] = id;
    }
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

/// [Handle] Method handle.
/// [param]  Param.
/// [cancelable] Cancel context.
typedef Handle = Future<dynamic> Function(
  dynamic param,
  Cancelable cancelable,
  Notify notify,
);

/// [Notify] Notify.
/// [param]  Param.
typedef Notify = Future<void> Function(
  dynamic param,
);
