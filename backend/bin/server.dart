import 'dart:io';
import 'package:aerodesk_backend/api_server.dart';

Future<void> main() async {
  final url = Platform.environment['DATABASE_URL'];
  if (url == null || url.isEmpty) {
    stderr.writeln('DATABASE_URL is required. Load the local .env.local first.');
    exitCode = 2;
    return;
  }
  final host = Platform.environment['API_HOST'] ?? '127.0.0.1';
  final port = int.tryParse(Platform.environment['API_PORT'] ?? '') ?? 4783;
  final app = await AeroDeskServer.open(url);
  final server = await app.serve(host: host, port: port);
  stdout.writeln('AeroDesk SQL API listening at http://${server.address.host}:${server.port}');
  ProcessSignal.sigint.watch().listen((_) async {
    await server.close(force: true);
    await app.close();
    exit(0);
  });
}
