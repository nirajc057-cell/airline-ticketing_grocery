import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'session_store.dart';

class ApiException implements Exception {
  final String message;
  final int status;
  const ApiException(this.message, this.status);
  @override
  String toString() => message;
}

class ApiClient {
  ApiClient({String? baseUrl}) : baseUrl = baseUrl ?? defaultBaseUrl;

  static String get defaultBaseUrl {
    const configured = String.fromEnvironment('API_BASE_URL');
    if (configured.isNotEmpty) return configured.replaceAll(RegExp(r'/$'), '');
    if (kIsWeb) {
      final host = Uri.base.host;
      if (host == 'localhost' || host == '127.0.0.1') {
        return 'http://127.0.0.1:4783';
      }
      return Uri.base.origin;
    }
    if (Platform.isAndroid) return 'http://10.0.2.2:4783';
    return 'http://127.0.0.1:4783';
  }

  String baseUrl;
  String? token = readSessionToken();

  Future<dynamic> request(String method, String path, [Object? body]) async {
    final headers = <String, String>{'Accept': 'application/json'};
    if (body != null) headers['Content-Type'] = 'application/json';
    if (token != null) headers['Authorization'] = 'Bearer $token';
    final request = http.Request(method, Uri.parse('$baseUrl$path'));
    request.headers.addAll(headers);
    if (body != null) request.body = jsonEncode(body);
    final client = http.Client();
    late final http.Response response;
    try {
      response = await http.Response.fromStream(await client.send(request));
    } on Exception {
      final local = {
        'localhost',
        '127.0.0.1',
        '10.0.2.2',
      }.contains(Uri.tryParse(baseUrl)?.host);
      throw ApiException(
        local
            ? 'Cannot reach the local backend. Start it from the backend PowerShell window.'
            : 'Cannot reach the server. Check your connection and try again.',
        0,
      );
    } finally {
      client.close();
    }
    dynamic result;
    try {
      result = jsonDecode(response.body);
    } catch (_) {
      result = null;
    }
    if (response.statusCode >= 400) {
      final message = result is Map ? result['error']?.toString() : null;
      throw ApiException(
        message ?? 'Request failed (${response.statusCode})',
        response.statusCode,
      );
    }
    return result;
  }

  Future<dynamic> get(String path) => request('GET', path);
  Future<dynamic> post(String path, Object body) => request('POST', path, body);
  Future<dynamic> patch(String path, Object body) =>
      request('PATCH', path, body);

  Future<Map<String, dynamic>> login(
    String email,
    String password,
    String otp,
  ) async {
    final result = Map<String, dynamic>.from(
      await post('/api/login', {
        'email': email.trim(),
        'password': password,
        'otp': otp.trim(),
      }),
    );
    token = result['token']?.toString();
    writeSessionToken(token);
    return result;
  }

  Future<void> logout() async {
    if (token != null) {
      try {
        await post('/api/logout', <String, dynamic>{});
      } catch (_) {}
    }
    token = null;
    writeSessionToken(null);
  }
}

Map<String, dynamic> asMap(dynamic value) =>
    value is Map
        ? value.map((key, val) => MapEntry(key.toString(), val))
        : <String, dynamic>{};

List<Map<String, dynamic>> asRows(dynamic value) =>
    value is List ? value.map(asMap).toList() : <Map<String, dynamic>>[];

String displayValue(dynamic value) {
  if (value == null || value == '') return '—';
  if (value is Map) {
    return value.entries
        .map((e) => '${e.key}: ${displayValue(e.value)}')
        .join(' · ');
  }
  if (value is List) return value.map(displayValue).join(', ');
  return value.toString();
}
