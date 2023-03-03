import 'dart:async';

import 'npc.dart';
import 'package:cancelable/cancelable.dart';

class NPCImpl implements NPC {
  NPCImpl();

  @override
  late FutureOr<void> Function(Message message) send;

  @override
  void on(
    String method,
    Handle? handle,
  ) {
    this[method] = handle;
  }

  @override
  Handle? operator [](String method) {
    return _handlers[method];
  }

  @override
  void operator []=(String method, Handle? handle) {
    if (handle == null) {
      _handlers.remove(method);
    } else {
      _handlers[method] = handle;
    }
  }

  @override
  FutureOr<void> emit(
    String method, {
    dynamic param,
  }) async {
    final m =
        Message(typ: Typ.emit, id: _nextId(), method: method, param: param);
    await send(m);
  }

  @override
  Future<dynamic> deliver(
    String method, {
    dynamic param,
    Duration? timeout,
    Cancelable? cancelable,
    Notify? onNotify,
  }) async {
    final completer = Completer.sync();
    Timer? timer = null;
    Disposable? disposable = null;
    final id = _nextId();
    final reply = (dynamic param, dynamic error) {
      if (completer.isCompleted) {
        return false;
      }
      if (error == null) {
        completer.complete(param);
      } else {
        completer.completeError(error);
      }
      timer?.cancel();
      _notifies.remove(id);
      _replies.remove(id);
      disposable?.dispose();
      return true;
    };
    _replies[id] = reply;
    if (onNotify != null) {
      _notifies[id] = (dynamic param) async {
        if (completer.isCompleted) {
          return;
        }
        try {
          await onNotify(param);
        } catch (e) {
          print(e);
        }
      };
    }
    if (cancelable != null) {
      disposable = cancelable.whenCancel(() async {
        try {
          if (await reply(null, 'cancelled') == true) {
            final m = Message(typ: Typ.cancel, id: id);
            send(m);
          }
        } catch (e) {
          print(e);
        }
      });
    }
    if (timeout != null && timeout.inMilliseconds > 0) {
      timer = Timer(timeout, () async {
        try {
          if (await reply(null, 'timedout') == true) {
            final m = Message(typ: Typ.cancel, id: id);
            send(m);
          }
        } catch (e) {
          print(e);
        }
      });
    }
    send(Message(typ: Typ.deliver, id: id, method: method, param: param));
    return completer.future;
  }

  @override
  Future<void> receive(Message message) async {
    switch (message.typ) {
      case Typ.emit:
        await _handlers[message.method]
            ?.call(message.param, Cancelable(), (_) async {});
        break;
      case Typ.deliver:
        final id = message.id;
        final handle = _handlers[message.method];
        if (handle == null) {
          final m = Message(typ: Typ.ack, id: id, error: 'unimplemented');
          send(m);
          break;
        }
        var completed = false;
        final cancelable = Cancelable();
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
            send(m);
          });
          if (completed) {
            return;
          }
          completed = true;
          _cancels.remove(id);
          final m = Message(typ: Typ.ack, id: id, param: r);
          send(m);
        } catch (e) {
          if (completed) {
            return;
          }
          completed = true;
          _cancels.remove(id);
          final m = Message(typ: Typ.ack, id: id, error: e);
          send(m);
        }
        break;
      case Typ.ack:
        _replies[message.id]?.call(message.param, message.error);
        break;
      case Typ.cancel:
        _cancels.remove(message.id)?.call();
        break;
      case Typ.notify:
        await _notifies[message.id]?.call(message.param);
        break;
      default:
        break;
    }
  }

  @override
  Future<void> cleanUpDeliveries(dynamic reason) async {
    final iterator = _replies.entries.iterator;
    while (iterator.moveNext()) {
      final reply = iterator.current.value;
      reply(null, reason);
    }
  }

  int _nextId() {
    if (_id < 0x7fffffff) {
      _id++;
    } else {
      _id = 0;
    }
    return _id;
  }

  var _id = -1;
  final _notifies = Map<int, Notify>();
  final _cancels = Map<int, Function()>();
  final _replies = Map<int, void Function(dynamic param, dynamic error)>();
  final _handlers = Map<String, Handle>();
}
