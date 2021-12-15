import 'dart:async';

import 'package:cancelable/cancelable.dart';
import 'package:meta/meta.dart';

class NPC {
  NPC(this._send);

  @mustCallSuper
  void on(
    String method,
    Handle handle,
  ) {
    _handlers[method] = handle;
  }

  @mustCallSuper
  Future<void> emit(
    String method, {
    dynamic param,
  }) async {
    final m = Message(typ: Typ.emit, method: method, param: param);
    await _send(m);
  }

  @mustCallSuper
  Future deliver(
    String method, {
    dynamic param,
    Duration? timeout,
    Cancelable? cancelable,
    Notify? onNotify,
  }) async {
    final completer = Completer();
    final id = _id++;
    Timer? timer = null;
    Disposable? disposable = null;
    final onReply = (dynamic param, dynamic error) async {
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
      await disposable?.dispose();
      return true;
    };
    if (onNotify != null) {
      _notifies[id] = onNotify;
    }
    if (cancelable != null) {
      disposable = cancelable.whenCancel(() async {
        if (await onReply(null, 'cancelled') == true) {
          final m = Message(typ: Typ.cancel, id: id);
          await _send(m);
        }
      });
    }
    if (timeout != null && timeout.inMicroseconds > 0) {
      timer = Timer(timeout, () async {
        if (await onReply(null, 'timedout') == true) {
          final m = Message(typ: Typ.cancel, id: id);
          await _send(m);
        }
      });
    }
    _replies[id] = onReply;
    final m = Message(typ: Typ.deliver, id: id, method: method, param: param);
    await _send(m);
    return completer.future;
  }

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
          _cancels.remove(id);
        };
        try {
          final r = await handle(message.param, cancelable, (param) async {
            if (completed) {
              return;
            }
            final m = Message(typ: Typ.notify, id: id, param: param);
            await _send(m);
          });
          if (completed) {
            return;
          }
          completed = true;
          _cancels.remove(id);
          final m = Message(typ: Typ.ack, id: id, param: r);
          await _send(m);
        } catch (e) {
          if (completed) {
            return;
          }
          completed = true;
          _cancels.remove(id);
          final m = Message(typ: Typ.ack, id: id, error: e);
          await _send(m);
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
        final cancel = _cancels[id];
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

  Future<void> Function(Message message) _send;

  final _notifies = Map<int, Notify>();
  final _cancels = Map<int, Function()>();
  final _replies = Map<int, Future<void> Function(dynamic param, dynamic error)>();
  final _handlers = Map<String, Handle>();
  var _id = 0;
}

typedef Handle = Future<dynamic> Function(
  dynamic param,
  Cancelable cancelable,
  Notify notify,
);

typedef Notify = Future<void> Function(
  dynamic param,
);

enum Typ {
  emit,
  deliver,
  notify,
  ack,
  cancel,
}

class Message {
  Message({
    required this.typ,
    this.id,
    this.method,
    this.param,
    this.error,
  });
  final Typ typ;
  final int? id;
  final String? method;
  final dynamic param;
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
