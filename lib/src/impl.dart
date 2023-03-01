import 'dart:async';

import 'package:npc/npc.dart';
import 'message.dart';

class NPCImpl implements NPC {
  NPCImpl();
  void on(
    String method,
    Handle handle,
  ) {
    _handlers[method] = handle;
  }

  Future<void> emit(
    String method, {
    dynamic param,
  }) async {
    await send(Message(typ: Typ.emit, method: method, param: param));
  }

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
      await disposable?.dispose();
      return true;
    };
    if (onNotify != null) {
      _notifies[id] = (dynamic param) async {
        if (completer.isCompleted) {
          return;
        }
        try {
          await onNotify(param);
        } catch (_) {}
      };
    }
    if (cancelable != null) {
      disposable = cancelable.whenCancel(() async {
        try {
          if (await reply(null, 'cancelled') == true) {
            send(Message(typ: Typ.cancel, id: id));
          }
        } catch (_) {}
      });
    }
    if (timeout != null && timeout.inMilliseconds > 0) {
      timer = Timer(timeout, () async {
        try {
          if (await reply(null, 'timedout') == true) {
            send(Message(typ: Typ.cancel, id: id));
          }
        } catch (_) {}
      });
    }
    _replies[id] = reply;
    send(Message(typ: Typ.deliver, id: id, method: method, param: param));
    return completer.future;
  }

  Future<void> cleanUpDeliveries(dynamic reason) async {
    final iterator = this._replies.entries.iterator;
    while (iterator.moveNext()) {
      final reply = iterator.current.value;
      await reply(null, reason);
    }
  }

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
          send(m);
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
            send(Message(typ: Typ.notify, id: id, param: param));
          });
          if (completed) {
            return;
          }
          _cancels.remove(id);
          completed = true;
          send(Message(typ: Typ.ack, id: id, param: r));
        } catch (e) {
          if (completed) {
            return;
          }
          _cancels.remove(id);
          completed = true;
          send(Message(typ: Typ.ack, id: id, error: e));
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

  late Future<void> Function(Message message) send;
  var _id = 0;
  final _notifies = Map<int, Notify>();
  final _cancels = Map<int, Function()>();
  final _replies =
      Map<int, Future<void> Function(dynamic param, dynamic error)>();
  final _handlers = Map<String, Handle>();
}
