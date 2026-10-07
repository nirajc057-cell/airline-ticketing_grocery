import 'package:postgres/postgres.dart';

Future<Connection> openDatabase(String connectionUrl) {
  final uri = Uri.parse(connectionUrl);
  final isLocal = {'127.0.0.1', 'localhost', '::1'}.contains(uri.host);
  final url = isLocal && !uri.queryParameters.containsKey('sslmode')
      ? uri.replace(queryParameters: {...uri.queryParameters, 'sslmode': 'disable'}).toString()
      : connectionUrl;
  return Connection.openFromUrl(url);
}
