import 'dart:async';

import 'package:npc/npc.dart';

import 'package:test/test.dart';

void main() {
  test('npc', () async {
    NPC c0 = NPC();
    NPC c1 = NPC();
    c0.send = (message) async {
      print(message);
      await c1.receive(message);
    };
    c1.send = (message) async {
      print(message);
      await c0.receive(message);
    };
    config(c0);
    config(c1);
    final r0 = await c0.deliver('ping');
    print(r0);
    final param = '/path';
    final r1 = await c1.deliver(
      'download',
      param: '/path',
      onNotify: (param) async {
        print(param);
      },
    );
    print(r1);
    expect(r0, 'pong');
    expect(r1, 'did download to $param');
  });
}

void config(NPC npc) {
  npc.on('ping', (param, cancelable, notify) async {
    return 'pong';
  });
  npc.on('download', (param, cancelable, notify) async {
    StreamSubscription? sub = null;
    Timer? timer = null;
    final completer = Completer<String>();
    var i = 0;
    timer = Timer.periodic(Duration(seconds: 1), (timer) async {
      i++;
      if (i < 10) {
        notify('${i}/10');
        return;
      }
      if (completer.isCompleted) {
        return;
      }
      timer.cancel();
      await sub?.cancel();
      completer.complete('did download to $param');
    });
    cancelable.whenCancel(() {
      if (completer.isCompleted) {
        return;
      }
      timer?.cancel();
      completer.completeError('cancelled');
    });
    final r = await completer.future;
    return r;
  });
}
