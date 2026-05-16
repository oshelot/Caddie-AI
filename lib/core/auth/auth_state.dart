// KAN-415: Auth state for optional Apple/Google sign-in.

enum AuthState {
  /// No account — fully functional guest mode.
  guest,

  /// Sign-in in progress (native IdP dialog visible).
  signingIn,

  /// Signed in with a Cognito-backed account.
  authenticated,

  /// Sign-in failed or tokens expired and refresh failed.
  error,
}
