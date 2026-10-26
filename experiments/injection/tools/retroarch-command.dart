import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  final replies = await commands(args);
  for (final reply in replies) stdout.writeln(reply);
}

Future<List<String>> commands(List<String> args) async {
  final replies = <String>[];
  final socket = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
  socket.listen((event) {
    if (event == RawSocketEvent.read) {
      final reply = socket.receive();
      if (reply != null) replies.add(utf8.decode(reply.data));
    }
  });
  for (final cmd in args) {
    socket.send(utf8.encode('$cmd\n'), InternetAddress.loopbackIPv4, 55355);
    await Future<void>.delayed(const Duration(milliseconds: 400));
  }
  socket.close();
  return replies;
}
