import 'session_store_stub.dart'
    if (dart.library.html) 'session_store_web.dart'
    as platform;

String? readSessionToken() => platform.readSessionToken();
void writeSessionToken(String? token) => platform.writeSessionToken(token);
