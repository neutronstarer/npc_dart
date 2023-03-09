import 'dart:async';

import 'npc.dart';
import 'package:cancelable/cancelable.dart';

class NPCImpl implements NPC {
  NPCImpl();
  @override
  void connect(void Function(Message p1) send) {
    disconnect();
    this._send = send;
  }

  @override
  void disconnect({reason}) {
    final error = reason ?? "disconnected";
    this
        ._replies
        .values
        .map((e) => e)
        .toList(growable: false)
        .forEach((element) {
      element(null, error);
    });
    this
        ._cancels
        .values
        .map((e) => e)
        .toList(growable: false)
        .forEach((element) {
      element();
    });
  }

  @override
  void on(
    String method,
    Handle? handle,
  ) {
    this[method] = handle;
  }

  @override
  Handle? operator [](String method) {
    return _handles[method];
  }

  @override
  void operator []=(String method, Handle? handle) {
    if (handle == null) {
      _handles.remove(method);
    } else {
      _handles[method] = handle;
    }
  }

  @override
  void emit(
    String method, {
    dynamic param,
  }) async {
    final m =
        Message(typ: Typ.emit, id: _nextId(), method: method, param: param);
    _send?.call(m);
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
      _notifies.remove(id);
      _replies.remove(id);
      timer?.cancel();
      disposable?.dispose();
      return true;
    };
    _replies[id] = reply;
    if (onNotify != null) {
      _notifies[id] = (dynamic param) async {
        if (completer.isCompleted) {
          return;
        }
        await onNotify(param);
      };
    }
    if (cancelable != null) {
      disposable = cancelable.whenCancel(() async {
        if (reply(null, 'cancelled') == true) {
          final m = Message(typ: Typ.cancel, id: id);
          _send?.call(m);
        }
      });
    }
    if (timeout != null && timeout.inMilliseconds > 0) {
      timer = Timer(timeout, () {
        if (reply(null, 'timedout') == true) {
          final m = Message(typ: Typ.cancel, id: id);
          _send?.call(m);
        }
      });
    }
    final m = Message(typ: Typ.deliver, id: id, method: method, param: param);
    _send?.call(m);
    return completer.future;
  }

  @override
  Future<void> receive(Message message) async {
    switch (message.typ) {
      case Typ.emit:
        final handle = _handles[message.method];
        if (handle == null) {
          print("[NPC] unhandled message: ${message}");
          break;
        }
        await handle(message.param, Cancelable(), (_) async {});
        break;
      case Typ.deliver:
        final id = message.id;
        final handle = _handles[message.method];
        if (handle == null) {
          print("[NPC] unhandled message: ${message}");
          final m = Message(
              typ: Typ.ack, id: id, param: null, error: "unimplemented");
          _send?.call(m);
          break;
        }
        var completed = false;
        final notify = (dynamic param) {
          if (completed) {
            return;
          }
          final m = Message(typ: Typ.notify, id: id, param: param);
          _send?.call(m);
        };
        final reply = (dynamic param, dynamic error) {
          if (completed) {
            return;
          }
          completed = true;
          _cancels.remove(id);
          final m = Message(typ: Typ.ack, id: id, param: param, error: error);
          _send?.call(m);
        };
        final cancelable = Cancelable();
        _cancels[id] = () {
          if (completed) {
            return;
          }
          completed = true;
          _cancels.remove(id);
          cancelable.cancel();
        };
        try {
          final r = await handle(message.param, cancelable, notify);
          reply(r, null);
        } catch (e) {
          reply(null, e);
        }
        break;
      case Typ.ack:
        _replies[message.id]?.call(message.param, message.error);
        break;
      case Typ.cancel:
        _cancels[message.id]?.call();
        break;
      case Typ.notify:
        await _notifies[message.id]?.call(message.param);
        break;
      default:
        break;
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
  final _cancels = Map<int, void Function()>();
  final _replies = Map<int, void Function(dynamic param, dynamic error)>();
  final _handles = Map<String, Handle>();
  void Function(Message message)? _send;
}
