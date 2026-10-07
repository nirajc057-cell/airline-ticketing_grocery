import 'package:web/web.dart' as web;

const _key = 'aerodeskFlutterToken';
String? readSessionToken() => web.window.localStorage.getItem(_key);
void writeSessionToken(String? token) {
  if (token == null) {
    web.window.localStorage.removeItem(_key);
  } else {
    web.window.localStorage.setItem(_key, token);
  }
}
