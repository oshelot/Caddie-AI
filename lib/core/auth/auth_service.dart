// KAN-415: Auth service for optional Apple/Google sign-in via Cognito.
//
// Flow:
//   1. Native IdP SDK (Apple/Google) → authorization code
//   2. Exchange code with Cognito TOKEN endpoint → JWTs
//   3. Store tokens in flutter_secure_storage
//   4. Decode id_token for user ID (sub claim)
//
// No Cognito SDK — plain HTTP via CognitoTokenClient.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../courses/http_transport.dart';
import '../storage/secure_keys_storage.dart';
import 'auth_state.dart';
import 'cognito_token_client.dart';

class AuthService extends ChangeNotifier {
  AuthService({
    required String cognitoDomain,
    required String cognitoClientId,
    required HttpTransport transport,
    this.googleServerClientId,
    SecureKeysStorage? secureKeys,
  })  : _tokenClient = CognitoTokenClient(
          domain: cognitoDomain,
          clientId: cognitoClientId,
          redirectUri: 'caddieai://callback',
          transport: transport,
        ),
        _secureKeys = secureKeys ?? SecureKeysStorage();

  final CognitoTokenClient _tokenClient;
  final SecureKeysStorage _secureKeys;
  final String? googleServerClientId;

  AuthState _state = AuthState.guest;
  String? _cognitoUserId;
  String? _authProvider;
  String? _email;
  String? _displayName;
  String? _accessToken;
  String? _idToken;
  String? _refreshToken;
  DateTime? _tokenExpiresAt;

  AuthState get state => _state;
  String? get cognitoUserId => _cognitoUserId;
  String? get authProvider => _authProvider;
  String? get email => _email;
  String? get displayName => _displayName;
  String? get accessToken => _accessToken;
  String? get idToken => _idToken;
  bool get isAuthenticated => _state == AuthState.authenticated;

  // ── Restore session on app start ─────────────────────────────────

  Future<void> restoreSession() async {
    final refreshToken = await _secureKeys.read(SecureKey.cognitoRefreshToken);
    if (refreshToken == null || refreshToken.isEmpty) return;

    _refreshToken = refreshToken;
    _cognitoUserId = await _secureKeys.read(SecureKey.cognitoUserId);
    _authProvider = await _secureKeys.read(SecureKey.authProvider);

    // Try to refresh tokens silently
    try {
      final tokens = await _tokenClient.refreshTokens(refreshToken);
      _applyTokens(tokens);
      _state = AuthState.authenticated;
    } catch (e) {
      debugPrint('AuthService: session restore failed: $e');
      _state = AuthState.guest;
    }
    notifyListeners();
  }

  // ── Sign in with Apple ───────────────────────────────────────────

  Future<AuthResult> signInWithApple() async {
    _state = AuthState.signingIn;
    notifyListeners();

    try {
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );

      if (credential.authorizationCode.isEmpty) {
        return _fail('Apple sign-in cancelled');
      }

      final tokens = await _tokenClient.exchangeCode(
        credential.authorizationCode,
      );

      _applyTokens(tokens);
      _authProvider = 'apple';

      // Apple only gives name on first sign-in — use it if available
      if (credential.givenName != null) {
        _displayName = [credential.givenName, credential.familyName]
            .where((s) => s != null && s.isNotEmpty)
            .join(' ');
      }

      await _persistTokens();
      _state = AuthState.authenticated;
      notifyListeners();
      return AuthResult.success(
        userId: _cognitoUserId!,
        email: _email,
        displayName: _displayName,
        provider: 'apple',
      );
    } catch (e) {
      return _fail('Apple sign-in failed: $e');
    }
  }

  // ── Sign in with Google (via Cognito Hosted UI) ──────────────────

  /// Launches the Cognito hosted UI in the system browser, which handles
  /// the Google OAuth redirect internally. The app receives the auth code
  /// via the `caddieai://callback?code=...` deep link.
  ///
  /// Call [handleCallbackUri] when the app receives the deep link.
  Future<void> signInWithGoogle() async {
    _state = AuthState.signingIn;
    _authProvider = 'google';
    notifyListeners();

    final uri = Uri.https(_tokenClient.domain, '/oauth2/authorize', {
      'response_type': 'code',
      'client_id': _tokenClient.clientId,
      'redirect_uri': _tokenClient.redirectUri,
      'scope': 'openid email profile',
      'identity_provider': 'Google',
    });

    try {
      // Launch URL in system browser without url_launcher dependency
      if (Platform.isAndroid) {
        await const MethodChannel('caddieai/auth')
            .invokeMethod('launchUrl', uri.toString());
      } else {
        // iOS: Process.run won't work; for now fall back to nothing
        // (Apple Sign In is the primary iOS flow)
        debugPrint('Google sign-in via hosted UI not yet supported on iOS');
      }
    } catch (e) {
      _fail('Could not launch sign-in: $e');
    }
  }

  /// Handle the callback deep link from Cognito hosted UI.
  /// Called by the app's deep link handler when `caddieai://callback?code=X` arrives.
  Future<AuthResult> handleCallbackUri(Uri uri) async {
    final code = uri.queryParameters['code'];
    final error = uri.queryParameters['error'];

    if (error != null) {
      return _fail('Sign-in error: $error');
    }
    if (code == null || code.isEmpty) {
      return _fail('No authorization code in callback');
    }

    try {
      final tokens = await _tokenClient.exchangeCode(code);
      _applyTokens(tokens);
      _authProvider ??= 'google';

      await _persistTokens();
      _state = AuthState.authenticated;
      notifyListeners();
      return AuthResult.success(
        userId: _cognitoUserId!,
        email: _email,
        displayName: _displayName,
        provider: _authProvider!,
      );
    } catch (e) {
      return _fail('Token exchange failed: $e');
    }
  }

  // ── Sign out ─────────────────────────────────────────────────────

  Future<void> signOut() async {
    if (_refreshToken != null) {
      try {
        await _tokenClient.revokeToken(_refreshToken!);
      } catch (_) {
        // Best-effort revoke
      }
    }

    await _clearTokens();
    _state = AuthState.guest;
    _cognitoUserId = null;
    _authProvider = null;
    _email = null;
    _displayName = null;
    _accessToken = null;
    _idToken = null;
    _refreshToken = null;
    _tokenExpiresAt = null;
    notifyListeners();
  }

  // ── Account deletion ──────────────────────────────────────────────

  /// Delete the user's account. Called from profile page.
  /// The actual cloud deletion is done by the sync client's
  /// deleteAccount() — this method just clears local auth state.
  Future<void> deleteAccount() async {
    await _clearTokens();
    _state = AuthState.guest;
    _cognitoUserId = null;
    _authProvider = null;
    _email = null;
    _displayName = null;
    _accessToken = null;
    _idToken = null;
    _refreshToken = null;
    _tokenExpiresAt = null;
    notifyListeners();
  }

  // ── Token refresh ────────────────────────────────────────────────

  Future<bool> refreshTokens() async {
    if (_refreshToken == null) return false;
    try {
      final tokens = await _tokenClient.refreshTokens(_refreshToken!);
      _applyTokens(tokens);
      await _persistTokens();
      return true;
    } catch (e) {
      debugPrint('AuthService: token refresh failed: $e');
      return false;
    }
  }

  /// Returns a valid access token, refreshing if needed.
  Future<String?> getValidAccessToken() async {
    if (_accessToken == null) return null;
    if (_tokenExpiresAt != null &&
        DateTime.now().isAfter(
          _tokenExpiresAt!.subtract(const Duration(minutes: 5)),
        )) {
      final ok = await refreshTokens();
      if (!ok) return null;
    }
    return _accessToken;
  }

  // ── Internals ────────────────────────────────────────────────────

  void _applyTokens(CognitoTokens tokens) {
    _accessToken = tokens.accessToken;
    _idToken = tokens.idToken;
    _refreshToken = tokens.refreshToken;
    _cognitoUserId = tokens.userId;
    _email = tokens.email;
    _displayName ??= tokens.name;
    _tokenExpiresAt = DateTime.now().add(
      Duration(seconds: tokens.expiresIn),
    );
  }

  Future<void> _persistTokens() async {
    await _secureKeys.write(SecureKey.cognitoAccessToken, _accessToken);
    await _secureKeys.write(SecureKey.cognitoIdToken, _idToken);
    await _secureKeys.write(SecureKey.cognitoRefreshToken, _refreshToken);
    await _secureKeys.write(SecureKey.cognitoUserId, _cognitoUserId);
    await _secureKeys.write(SecureKey.authProvider, _authProvider);
  }

  Future<void> _clearTokens() async {
    for (final key in [
      SecureKey.cognitoAccessToken,
      SecureKey.cognitoIdToken,
      SecureKey.cognitoRefreshToken,
      SecureKey.cognitoUserId,
      SecureKey.authProvider,
    ]) {
      await _secureKeys.write(key, null);
    }
  }

  AuthResult _fail(String message) {
    debugPrint('AuthService: $message');
    _state = AuthState.error;
    notifyListeners();
    // Reset to guest after a brief error state
    Future.delayed(const Duration(seconds: 2), () {
      if (_state == AuthState.error) {
        _state = AuthState.guest;
        notifyListeners();
      }
    });
    return AuthResult.failure(message);
  }
}

class AuthResult {
  const AuthResult._({
    required this.success,
    this.userId,
    this.email,
    this.displayName,
    this.provider,
    this.error,
  });

  factory AuthResult.success({
    required String userId,
    String? email,
    String? displayName,
    required String provider,
  }) =>
      AuthResult._(
        success: true,
        userId: userId,
        email: email,
        displayName: displayName,
        provider: provider,
      );

  factory AuthResult.failure(String error) =>
      AuthResult._(success: false, error: error);

  final bool success;
  final String? userId;
  final String? email;
  final String? displayName;
  final String? provider;
  final String? error;
}
