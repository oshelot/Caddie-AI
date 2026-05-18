// KAN-415: Auth service for optional Apple/Google sign-in via Cognito.
//
// Flow:
//   1. Native IdP SDK (Apple/Google) → authorization code
//   2. Exchange code with Cognito TOKEN endpoint → JWTs
//   3. Store tokens in flutter_secure_storage
//   4. Decode id_token for user ID (sub claim)
//
// No Cognito SDK — plain HTTP via CognitoTokenClient.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

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

  /// Completes when an awaited sign-in (Apple) finishes its OAuth
  /// round-trip via [handleCallbackUri]. Google uses the listener
  /// pattern instead and leaves this null.
  Completer<AuthResult>? _pendingAuth;

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

  // ── Hosted-UI sign-in (Apple + Google) ───────────────────────────
  //
  // Both providers federate through the Cognito hosted UI: the app
  // opens `/oauth2/authorize?identity_provider=...`, Cognito brokers
  // the IdP handshake and redirects to `caddieai://callback?code=...`
  // with a *Cognito-issued* code. The native layer (AppDelegate.swift
  // on iOS, MainActivity.kt on Android) launches the URL and streams
  // the callback back over the `caddieai/deeplink` EventChannel, which
  // `main.dart` routes into [handleCallbackUri].
  //
  // This is the only Cognito-supported way to federate Apple/Google
  // into a User Pool — the token endpoint only accepts codes Cognito
  // itself issued, so a native-SDK auth code cannot be exchanged here.

  /// Launches Apple sign-in via the Cognito hosted UI and resolves
  /// once the OAuth round-trip completes (or times out / is cancelled).
  Future<AuthResult> signInWithApple() async {
    _state = AuthState.signingIn;
    _authProvider = 'apple';
    notifyListeners();

    final completer = Completer<AuthResult>();
    _pendingAuth = completer;

    await _launchHostedUi('SignInWithApple');

    return completer.future.timeout(
      const Duration(seconds: 120),
      onTimeout: () => _fail('Apple sign-in timed out'),
    );
  }

  /// Launches Google sign-in via the Cognito hosted UI. The result
  /// arrives asynchronously through [handleCallbackUri]; callers
  /// observe the outcome via the [ChangeNotifier] listener (see the
  /// profile / onboarding screens).
  Future<void> signInWithGoogle() async {
    _state = AuthState.signingIn;
    _authProvider = 'google';
    notifyListeners();

    await _launchHostedUi('Google');
  }

  /// Builds the Cognito `/oauth2/authorize` URL for [identityProvider]
  /// and hands it to the native layer to open in a web-auth session.
  Future<void> _launchHostedUi(String identityProvider) async {
    final uri = Uri.https(_tokenClient.domain, '/oauth2/authorize', {
      'response_type': 'code',
      'client_id': _tokenClient.clientId,
      'redirect_uri': _tokenClient.redirectUri,
      'scope': 'openid email profile',
      'identity_provider': identityProvider,
    });

    try {
      await const MethodChannel('caddieai/auth')
          .invokeMethod('launchUrl', uri.toString());
    } catch (e) {
      _fail('Could not launch sign-in: $e');
    }
  }

  /// Handle the callback deep link from the Cognito hosted UI.
  /// Called by the app's deep link handler when
  /// `caddieai://callback?code=X` (or `?error=...`) arrives.
  Future<AuthResult> handleCallbackUri(Uri uri) async {
    final result = await _exchangeCallback(uri);
    // Resolve any awaited sign-in (Apple); Google leaves _pendingAuth null.
    final pending = _pendingAuth;
    _pendingAuth = null;
    if (pending != null && !pending.isCompleted) pending.complete(result);
    return result;
  }

  Future<AuthResult> _exchangeCallback(Uri uri) async {
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
