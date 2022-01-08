import 'dart:async';

import 'package:cancelable/cancelable.dart';
import 'package:meta/meta.dart';

/// [NPC] Near Procedure Call
class NPC {
  /// [NPC] Create instance.
  /// If [send] is null, you should extends NPC and override send().
  /// [send] Send message function
  NPC(Future<void> Function(Message message)? send) {
    if (send == null) {
      _send = (Message message) async {
        await this.send(message);
      };
      return;
    }
    _send = send;
  }

  /// [on] Register method handle.
  /// [method] Method name.
  /// [handle] Handle.
  @mustCallSuper
  void on(
    String method,
    Handle handle,
  ) {
    _handlers[method] = handle;
  }

  /// [emit] Emit method without reply.
  /// [method] Method name.
  /// [param] Method param.
  @mustCallSuper
  Future<void> emit(
    String method, {
    dynamic param,
  }) async {
    await _send(Message(typ: Typ.emit, method: method, param: param));
  }

  /// [deliver] Deliver method with reply.
  /// [method] Method name.
  /// [param] Method param.
  /// [timeout] Timeout.
  /// [cancelable] Cancel context.
  /// [onNotify] Called when notified.
  @mustCallSuper
  Future deliver(
    String method, {
    dynamic param,
    Duration? timeout,
    Cancelable? cancelable,
    Notify? onNotify,
  }) async {
    final completer = Completer.sync();
    final id = _id++;
    Timer? timer = null;
    Disposable? disposable = null;
    final reply = (dynamic param, dynamic error) async {
      if (completer.isCompleted) {
        return false;
      }
      if (error == null) {
        completer.complete(param);
      } else {
        completer.completeError(error);
      }
      _notifies.remove(id);
      _replies.remove(id);
      timer?.cancel();
      disposable?.dispose();
      return true;
    };
    if (onNotify != null) {
      _notifies[id] = (dynamic param) async {
        if (completer.isCompleted){
          return;
        }
        onNotify(param);
      };
    }
    if (cancelable != null) {
      disposable = cancelable.whenCancel(() async {
        if (await reply(null, 'cancelled') == true) {
          await _send(Message(typ: Typ.cancel, id: id));
        }
      });
    }
    if (timeout != null && timeout.inMilliseconds > 0) {
      timer = Timer(timeout, () async {
        if (await reply(null, 'timedout') == true) {
          await _send(Message(typ: Typ.cancel, id: id));
        }
      });
    }
    _replies[id] = reply;
    await _send(Message(typ: Typ.deliver, id: id, method: method, param: param));
    return completer.future;
  }

  /// [send] If [_send] is null, this function should be call to send message.
  Future<void> send(Message message) async {}

  /// [cleanUpDeliveries] Clean up all deliveries with special reason.
  /// [reason] error.
  @mustCallSuper
  Future<void> cleanUpDeliveries(dynamic reason) async{
    final iterator = this._replies.entries.iterator;
    while (iterator.moveNext()) {
        final reply = iterator.current.value;
        await reply(null, reason);
    }
  }
  /// [receive] Receive message.
  /// [message] Message.
  @mustCallSuper
  Future<void> receive(Message message) async {
    switch (message.typ) {
      case Typ.emit:
        final method = message.method;
        if (method == null) {
          break;
        }
        final handle = _handlers[method];
        if (handle == null) {
          break;
        }
        await handle(message.param, Cancelable(), (_) async {});
        break;
      case Typ.deliver:
        final id = message.id;
        if (id == null) {
          break;
        }
        final method = message.method;
        if (method == null) {
          break;
        }
        final handle = _handlers[method];
        if (handle == null) {
          final m = Message(typ: Typ.ack, id: id, error: 'unimplemented');
          await _send(m);
          break;
        }
        final cancelable = Cancelable();
        var completed = false;
        _cancels[id] = () {
          if (completed) {
            return;
          }
          completed = true;
          cancelable.cancel();
        };
        try {
          final r = await handle(message.param, cancelable, (param) async {
            if (completed) {
              return;
            }
            await _send(Message(typ: Typ.notify, id: id, param: param));
          });
          if (completed) {
            return;
          }
          _cancels.remove(id);
          completed = true;
          await _send(Message(typ: Typ.ack, id: id, param: r));
        } catch (e) {
          if (completed) {
            return;
          }
          _cancels.remove(id);
          completed = true;
          await _send(Message(typ: Typ.ack, id: id, error: e));
        }
        break;
      case Typ.ack:
        final id = message.id;
        if (id == null) {
          break;
        }
        final reply = _replies[id];
        if (reply == null) {
          break;
        }
        await reply(message.param, message.error);
        break;
      case Typ.cancel:
        final id = message.id;
        if (id == null) {
          break;
        }
        final cancel = _cancels.remove(id);
        if (cancel == null) {
          break;
        }
        cancel();
        break;
      case Typ.notify:
        final id = message.id;
        if (id == null) {
          break;
        }
        final notify = _notifies[id];
        if (notify == null) {
          break;
        }
        await notify(message.param);
        break;
      default:
        break;
    }
  }

  late Future<void> Function(Message message) _send;

  final _notifies = Map<int, Notify>();
  final _cancels = Map<int, Function()>();
  final _replies = Map<int, Future<void> Function(dynamic param, dynamic error)>();
  final _handlers = Map<String, Handle>();
  var _id = 0;
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
