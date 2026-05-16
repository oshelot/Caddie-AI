// KAN-415: Thin HTTP client for Cognito TOKEN endpoint.
// No Cognito SDK — exchanges IdP auth codes for Cognito JWTs via plain HTTP.

import 'dart:convert';

import '../courses/http_transport.dart';

class CognitoTokenClient {
  CognitoTokenClient({
    required this.domain,
    required this.clientId,
    required this.redirectUri,
    required HttpTransport transport,
  }) : _transport = transport;

  /// Cognito hosted UI domain, e.g. "caddieai.auth.us-east-2.amazoncognito.com"
  final String domain;

  /// Cognito App Client ID (public, no secret).
  final String clientId;

  /// OAuth callback URI registered on the client, e.g. "caddieai://callback"
  final String redirectUri;

  final HttpTransport _transport;

  /// Exchange an authorization code (from Apple/Google native SDK) for
  /// Cognito access, id, and refresh tokens.
  Future<CognitoTokens> exchangeCode(String authorizationCode) async {
    final resp = await _transport.send(HttpRequestLike(
      method: 'POST',
      url: Uri.https(domain, '/oauth2/token'),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: Uri(queryParameters: {
        'grant_type': 'authorization_code',
        'client_id': clientId,
        'code': authorizationCode,
        'redirect_uri': redirectUri,
      }).query,
      timeout: const Duration(seconds: 10),
    ));

    if (resp.statusCode != 200) {
      throw CognitoTokenException(
        'Token exchange failed: ${resp.statusCode}',
        resp.body,
      );
    }

    return CognitoTokens.fromJson(
      jsonDecode(resp.body) as Map<String, dynamic>,
    );
  }

  /// Refresh the access and id tokens using a refresh token.
  Future<CognitoTokens> refreshTokens(String refreshToken) async {
    final resp = await _transport.send(HttpRequestLike(
      method: 'POST',
      url: Uri.https(domain, '/oauth2/token'),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: Uri(queryParameters: {
        'grant_type': 'refresh_token',
        'client_id': clientId,
        'refresh_token': refreshToken,
      }).query,
      timeout: const Duration(seconds: 10),
    ));

    if (resp.statusCode != 200) {
      throw CognitoTokenException(
        'Token refresh failed: ${resp.statusCode}',
        resp.body,
      );
    }

    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    // Refresh response doesn't include a new refresh_token — keep the old one.
    return CognitoTokens(
      accessToken: json['access_token'] as String,
      idToken: json['id_token'] as String,
      refreshToken: refreshToken,
      expiresIn: json['expires_in'] as int? ?? 3600,
    );
  }

  /// Revoke the refresh token (used on sign-out).
  Future<void> revokeToken(String refreshToken) async {
    await _transport.send(HttpRequestLike(
      method: 'POST',
      url: Uri.https(domain, '/oauth2/revoke'),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: Uri(queryParameters: {
        'client_id': clientId,
        'token': refreshToken,
      }).query,
      timeout: const Duration(seconds: 10),
    ));
  }
}

class CognitoTokens {
  const CognitoTokens({
    required this.accessToken,
    required this.idToken,
    required this.refreshToken,
    required this.expiresIn,
  });

  final String accessToken;
  final String idToken;
  final String refreshToken;
  final int expiresIn; // seconds

  factory CognitoTokens.fromJson(Map<String, dynamic> json) {
    return CognitoTokens(
      accessToken: json['access_token'] as String,
      idToken: json['id_token'] as String,
      refreshToken: json['refresh_token'] as String,
      expiresIn: json['expires_in'] as int? ?? 3600,
    );
  }

  /// Decode the id_token payload (JWT part 1) to extract claims.
  /// Does NOT validate the signature — that's the backend's job.
  Map<String, dynamic> get idTokenClaims {
    final parts = idToken.split('.');
    if (parts.length != 3) return {};
    final payload = parts[1];
    final normalized = base64Url.normalize(payload);
    return jsonDecode(utf8.decode(base64Url.decode(normalized)))
        as Map<String, dynamic>;
  }

  /// Cognito user ID (the `sub` claim).
  String? get userId => idTokenClaims['sub'] as String?;

  /// Email from the identity provider (may be Apple private relay).
  String? get email => idTokenClaims['email'] as String?;

  /// Display name from the identity provider.
  String? get name {
    final claims = idTokenClaims;
    return claims['name'] as String? ??
        claims['given_name'] as String?;
  }
}

class CognitoTokenException implements Exception {
  const CognitoTokenException(this.message, this.responseBody);
  final String message;
  final String responseBody;

  @override
  String toString() => 'CognitoTokenException: $message';
}
