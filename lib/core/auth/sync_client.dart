// KAN-416: HTTP client for the user-sync Lambda.
// Injects Authorization: Bearer <id_token> on every request.
// Handles 401 → refresh → retry once.

import 'dart:convert';

import '../courses/http_transport.dart';
import 'auth_service.dart';

class SyncClient {
  SyncClient({
    required String endpoint,
    required AuthService authService,
    required HttpTransport transport,
  })  : _endpoint = endpoint.endsWith('/') ? endpoint.substring(0, endpoint.length - 1) : endpoint,
        _authService = authService,
        _transport = transport;

  final String _endpoint;
  final AuthService _authService;
  final HttpTransport _transport;

  /// PUT /sync — upsert a user data record.
  Future<SyncResponse> put({
    required String dataType,
    required String dataId,
    required Map<String, dynamic> data,
    required int updatedAtMs,
    int version = 1,
  }) async {
    return _send(HttpRequestLike(
      method: 'PUT',
      url: Uri.parse('$_endpoint/sync'),
      headers: await _headers(),
      body: jsonEncode({
        'dataType': dataType,
        'dataId': dataId,
        'data': data,
        'updatedAtMs': updatedAtMs,
        'version': version,
      }),
    ));
  }

  /// GET /sync?dataType=X — list all records of a type.
  Future<SyncResponse> list(String dataType) async {
    return _send(HttpRequestLike(
      method: 'GET',
      url: Uri.parse('$_endpoint/sync').replace(
        queryParameters: {'dataType': dataType},
      ),
      headers: await _headers(),
    ));
  }

  /// GET /sync/<type>/<id> — get a single record.
  Future<SyncResponse> get(String dataType, String dataId) async {
    return _send(HttpRequestLike(
      method: 'GET',
      url: Uri.parse('$_endpoint/sync/$dataType/$dataId'),
      headers: await _headers(),
    ));
  }

  /// DELETE /account — delete user account and all cloud data.
  Future<SyncResponse> deleteAccount() async {
    return _send(HttpRequestLike(
      method: 'DELETE',
      url: Uri.parse('$_endpoint/account'),
      headers: await _headers(),
    ));
  }

  Future<Map<String, String>> _headers() async {
    final token = await _authService.getValidAccessToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  /// Send with 401 retry — refresh token and retry once.
  Future<SyncResponse> _send(HttpRequestLike request) async {
    var resp = await _transport.send(request);

    if (resp.statusCode == 401) {
      final refreshed = await _authService.refreshTokens();
      if (refreshed) {
        final newHeaders = await _headers();
        resp = await _transport.send(HttpRequestLike(
          method: request.method,
          url: request.url,
          headers: newHeaders,
          body: request.body,
          timeout: request.timeout,
        ));
      }
    }

    return SyncResponse(
      statusCode: resp.statusCode,
      body: resp.body.isNotEmpty
          ? jsonDecode(resp.body) as Map<String, dynamic>
          : {},
    );
  }
}

class SyncResponse {
  const SyncResponse({required this.statusCode, required this.body});

  final int statusCode;
  final Map<String, dynamic> body;

  bool get ok => statusCode >= 200 && statusCode < 300;
  String? get error => body['error'] as String?;
}
