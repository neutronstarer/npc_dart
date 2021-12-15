# Near Procedure Call.

## Usage

```dart
// Create a NPC
final npc = NPC((message) async{
    // send message
});
```

```dart
//call when message received:
await npc.receive(message);
```

``` dart
// register handle
npc.on('ping', (param, cancelable, notify)=>'pong');
```

``` dart
// emit
await npc.emit('say', 'hello');
```

``` dart
// deliver
final r =await npc.deliver('download', param: '/path', onNotify: (param){

});
```

## Try the example for more usage.