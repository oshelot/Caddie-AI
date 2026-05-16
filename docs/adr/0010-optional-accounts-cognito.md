# 0010. Optional accounts with AWS Cognito

**Status:** Accepted
**Date proposed:** 2026-05-15
**Date accepted:** 2026-05-15
**Affected stories:** KAN-410 (epic), KAN-411 through KAN-419
**Depends on:** ADR 0004 (storage library)

## Context

CaddieAI stores all user data (profile, rounds, scorecards, club bag) locally
on-device in Hive. There is no user identity, no cross-device sync, and no
cloud backup. If a user loses their phone, their round history and
configuration are gone.

Users have asked for the ability to continue on a new device. The app also
needs verified identity for future features (social scoring, handicap
tracking, subscription ownership).

### Requirements

- Login is **optional** — guest mode must remain fully functional.
- Only Apple and Google sign-in. No passwords, no Facebook, no phone OTP.
- Cloud sync for profile, rounds, scorecards, club bag.
- Guest data migrates into the account on first sign-in.
- In-app account deletion (Apple App Store requirement).
- Existing API-key auth on course/LLM/logging lambdas is unchanged.

### Options considered

| Option | Pros | Cons |
|--------|------|------|
| **Firebase Auth** | Rich Flutter SDK, built-in UI | Adds a GCP dependency to an all-AWS stack; complicates IAM; vendor lock-in on auth |
| **AWS Cognito User Pools** | Same AWS account, native IAM integration, Apple+Google federation built-in | Flutter SDK is heavier than needed; hosted UI is basic |
| **Custom auth (JWT server)** | Full control | Significant build/maintain cost; reinventing solved problems |
| **Supabase Auth** | Good DX, Postgres-native | Another vendor; migration path unclear |

## Decision

**Use AWS Cognito User Pools with Apple and Google as federated identity
providers.** No Cognito SDK in the Flutter app — use the native IdP packages
(`sign_in_with_apple`, `google_sign_in`) to get an authorization code, then
exchange it with Cognito's TOKEN endpoint via plain HTTP.

### Architecture

```
┌─────────────┐     ┌──────────────┐     ┌──────────────┐
│  Flutter App │────▶│ Apple/Google │────▶│    Cognito    │
│             │◀────│  Native SDK  │◀────│  User Pool   │
│             │     └──────────────┘     └──────┬───────┘
│             │                                 │
│             │  Authorization: Bearer <JWT>    │
│             │────────────────────────────────▶│
│             │     ┌──────────────┐     ┌──────┴───────┐
│             │◀────│  user-sync   │◀────│  DynamoDB    │
│             │     │   Lambda     │     │  user-data   │
└─────────────┘     └──────────────┘     └──────────────┘
```

1. User taps "Sign in with Google/Apple" on Profile tab.
2. Native SDK handles OAuth → returns authorization code.
3. App POSTs code to Cognito TOKEN endpoint → receives access/id/refresh tokens.
4. Tokens stored in `flutter_secure_storage` (Keychain/EncryptedSharedPrefs).
5. User data sync goes to a new `caddieai-user-sync` Lambda that validates
   the Cognito JWT and reads/writes DynamoDB scoped to the user's `sub` claim.
6. Existing lambdas (course-cache, llm-proxy, logging) keep API-key auth —
   they serve anonymous, non-user-specific data.

### Why no Cognito SDK

The `amazon_cognito_identity_dart_2` package is 3,500+ lines, pulls in
multiple transitive dependencies, and does far more than we need (SRP auth,
MFA, device tracking). Our flow is simple: native IdP → auth code → one HTTP
POST to Cognito. The existing `HttpTransport` class handles this cleanly.

### Token lifecycle

- **Access token**: 1 hour (Cognito default). Used as Bearer token on
  user-sync Lambda calls.
- **Refresh token**: 30 days. Stored in secure storage. Used to get new
  access tokens without re-authenticating.
- **ID token**: 1 hour. Decoded client-side to extract `sub` (user ID),
  email, and name claims.

### User identity model

- Primary key: `cognitoUserId` (the `sub` claim from the JWT).
- Never key on email — Apple private relay can generate different addresses.
- `PlayerProfile` gains three fields: `cognitoUserId`, `authProvider`,
  `cloudSyncEnabled`. All nullable/defaulted for backward compat.
- `ScorecardEntry.playerIdentity` continues to store the local email/phone
  for display. The `cognitoUserId` is the authoritative owner identity.

### Cloud data model (DynamoDB)

Single table `caddieai-user-data`:
- PK: `userId` (Cognito sub)
- SK: `dataType#dataId` (e.g. `profile#self`, `scorecard#<uuid>`)
- Attributes: `data` (JSON), `updatedAtMs`, `version`
- TTL: `deletedAtMs` (for account deletion — 30-day purge)
- Conflict resolution: optimistic concurrency via version check
  (last-write-wins when versions match; reject when stale)

### Sync strategy

- **Offline-first**: all writes go to Hive first, then async push to cloud.
- **Sync queue**: failed pushes go to a `caddieai_sync_queue_v1` Hive box,
  drained on app resume / connectivity restore.
- **Guest → account migration**: on first sign-in, `pushAllLocal()` uploads
  all existing Hive data to the cloud.
- **New device sign-in**: `pullAll()` fetches cloud data and merges with
  local (last-write-wins by `updatedAtMs`).

### What stays unchanged

- Course search, map rendering, LLM proxy — all anonymous, API-key auth.
- Onboarding flow — sign-in is accessible from Profile tab, not required.
- Hive remains the source of truth for all local reads. Cloud is a
  replication target, not the primary store.

## Consequences

- **Positive**: Cross-device sync, verified identity for future features,
  account deletion compliance, no new vendor dependency.
- **Negative**: Cognito adds operational surface (user pool config, token
  refresh edge cases). DynamoDB adds a table to manage.
- **Risk**: Apple Sign-In on Android goes through Cognito's hosted UI
  web redirect (not native). Must test this flow explicitly.

## Security requirements (from KAN-410)

- Minimum OAuth scopes: openid, email, profile.
- Validate JWT server-side: issuer, audience, expiration, signature via JWKS.
- Store tokens in platform secure storage only.
- Backend scopes all queries to `userId = sub` — never trust client-supplied userId.
- No PII in logs.
- Account deletion removes/anonymizes all cloud-stored user data.
