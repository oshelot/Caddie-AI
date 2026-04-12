// ProfileScreen — KAN-283 (S13). Editor for the player profile.
// The screen takes a `PlayerProfile` and notifies the parent
// (via `onSave`) when the user commits changes. The parent is
// responsible for persisting via `ProfileRepository` and writing
// secure-store API keys via `SecureKeysStorage`.
//
// **Architecture: pure widget with constructor injection.** The
// page wrapper does the I/O; the leaf widget is a pure form
// renderer + edit state.
//
// **Critical safety invariant:** API keys are entered via this
// screen but **never appear on the `PlayerProfile` model** —
// they're handed to the parent via the `onSaveApiKeys` callback,
// which writes them to `SecureKeysStorage`. The dedicated test
// `test/storage/secure_keys_isolation_test.dart` (S2) is the
// canary; this screen MUST NOT add an apiKey field to the
// PlayerProfile copy it builds in `_save()`.

import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';

import '../../../core/icons/caddie_icons.dart';
import '../../../core/monetization/subscription_service.dart';
import '../../../core/storage/secure_keys_storage.dart';
import '../../../models/player_profile.dart';

/// One round-trippable bundle of changes the user can save. The
/// page wrapper unpacks this into a `PlayerProfile` write and a
/// secret-keys write.
class ProfileSaveRequest {
  const ProfileSaveRequest({
    required this.profile,
    required this.secrets,
  });

  /// The new profile (NEVER contains API key fields).
  final PlayerProfile profile;

  /// Secret-key updates keyed by `SecureKey` constants. Empty
  /// values are sentinels meaning "delete this key from secure
  /// storage". Pass to `SecureKeysStorage.writeAll`.
  final Map<String, String?> secrets;
}

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    required this.profile,
    required this.onSave,
    this.initialSecrets = const {},
    this.subscriptionService,
    this.showDebugSection = kDebugMode,
  });

  final PlayerProfile profile;
  final Future<void> Function(ProfileSaveRequest request) onSave;

  /// Pre-populated secret values to display in the API settings
  /// section (the page wrapper reads them from
  /// `SecureKeysStorage.read` before passing them in). The
  /// screen edits them locally; the changes flow back to the
  /// parent via `onSave`.
  final Map<String, String> initialSecrets;

  /// Optional injected subscription service. When provided AND
  /// [showDebugSection] is true, the screen renders the KAN-95
  /// debug section with a "Force Pro tier" toggle bound to
  /// `SubscriptionService.debugForcePro`.
  final SubscriptionService? subscriptionService;

  /// Whether to render the KAN-95 debug section. Defaults to
  /// `kDebugMode`, so release builds never see it. Tests pass
  /// `true` explicitly to exercise the toggle.
  final bool showDebugSection;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late PlayerProfile _draft = widget.profile;
  late final TextEditingController _nameController =
      TextEditingController(text: widget.profile.name);
  late final TextEditingController _emailController =
      TextEditingController(text: widget.profile.email);

  // API key controllers — values land in secure storage on save.
  // Initialized from the parent's `initialSecrets` map.
  late final TextEditingController _openAiKeyController =
      TextEditingController(text: widget.initialSecrets[SecureKey.openAi] ?? '');
  late final TextEditingController _claudeKeyController =
      TextEditingController(text: widget.initialSecrets[SecureKey.claude] ?? '');
  late final TextEditingController _geminiKeyController =
      TextEditingController(text: widget.initialSecrets[SecureKey.gemini] ?? '');

  bool _saving = false;

  // KAN-95 debug section state. Mirrors SubscriptionService.isSubscribed
  // and rebuilds via the stream subscription so the caption flips
  // immediately when the user toggles "Force Pro".
  StreamSubscription<bool>? _subSubscription;
  late bool _isSubscribed = widget.subscriptionService?.isSubscribed ?? false;

  bool get _shouldShowDebugSection =>
      widget.showDebugSection && widget.subscriptionService != null;

  @override
  void initState() {
    super.initState();
    final service = widget.subscriptionService;
    if (service != null) {
      _subSubscription = service.subscriptionStream.listen((value) {
        if (!mounted) return;
        setState(() => _isSubscribed = value);
      });
    }
  }

  @override
  void dispose() {
    _subSubscription?.cancel();
    _nameController.dispose();
    _emailController.dispose();
    _openAiKeyController.dispose();
    _claudeKeyController.dispose();
    _geminiKeyController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final updated = _draft.copyWith(
      name: _nameController.text.trim(),
      email: _emailController.text.trim(),
    );
    final request = ProfileSaveRequest(
      profile: updated,
      secrets: {
        SecureKey.openAi: _openAiKeyController.text.trim(),
        SecureKey.claude: _claudeKeyController.text.trim(),
        SecureKey.gemini: _geminiKeyController.text.trim(),
      },
    );
    await widget.onSave(request);
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Profile saved')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        leading: Padding(
          padding: const EdgeInsets.all(8),
          child: CaddieIcons.profile(
            size: 24,
            color: theme.colorScheme.onSurface,
          ),
        ),
        actions: [
          TextButton(
            key: const Key('profile-save-button'),
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          // ── Player Info card ─────────────────────────────────────
          // Mirrors Android ProfileScreen.kt:88-123
          _ProfileCard(
            title: 'Player Info',
            theme: theme,
            children: [
              TextField(
                key: const Key('profile-name-field'),
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  border: OutlineInputBorder(),
                ),
              ),
              TextField(
                key: const Key('profile-email-field'),
                controller: _emailController,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  border: OutlineInputBorder(),
                ),
              ),
              _SliderRow(
                key: const Key('profile-handicap-slider'),
                label: 'Handicap',
                value: _draft.handicap,
                min: 0,
                max: 36,
                divisions: 36,
                displayValue: _draft.handicap.toStringAsFixed(1),
                onChanged: (v) => setState(
                  () => _draft = _draft.copyWith(handicap: v),
                ),
              ),
              _stringDropdown(
                key: const Key('profile-aggressiveness'),
                label: 'Aggressiveness',
                value: _draft.aggressiveness,
                options: const ['conservative', 'normal', 'aggressive'],
                onChanged: (v) =>
                    setState(() => _draft = _draft.copyWith(aggressiveness: v)),
              ),
              _stringDropdown(
                key: const Key('profile-tee-box'),
                label: 'Preferred tee box',
                value: _draft.preferredTeeBox,
                options: const [
                  'championship',
                  'blue',
                  'white',
                  'senior',
                  'forward',
                ],
                onChanged: (v) =>
                    setState(() => _draft = _draft.copyWith(preferredTeeBox: v)),
              ),
            ],
          ),
          // ── Caddie Voice & Personality card ──────────────────────
          // Mirrors Android ProfileScreen.kt:126-151
          _ProfileCard(
            title: 'Caddie Voice & Personality',
            theme: theme,
            children: [
              _stringDropdown(
                key: const Key('profile-voice-gender'),
                label: 'Voice gender',
                value: _draft.caddieVoiceGender,
                options: const ['male', 'female'],
                onChanged: (v) => setState(
                  () => _draft = _draft.copyWith(caddieVoiceGender: v),
                ),
              ),
              _stringDropdown(
                key: const Key('profile-voice-accent'),
                label: 'Voice accent',
                value: _draft.caddieVoiceAccent,
                options: const [
                  'american',
                  'british',
                  'scottish',
                  'irish',
                  'australian',
                ],
                onChanged: (v) => setState(
                  () => _draft = _draft.copyWith(caddieVoiceAccent: v),
                ),
              ),
            ],
          ),
          // ── Features card ───────────────────────────────────────
          // Mirrors Android ProfileScreen.kt:178-208 and
          // iOS ProfileView.swift:88-103
          _ProfileCard(
            title: 'Features',
            theme: theme,
            children: [
              SwitchListTile(
                key: const Key('profile-telemetry-toggle'),
                title: const Text('Telemetry'),
                subtitle: const Text(
                  'Send anonymous usage stats to help improve recommendations.',
                ),
                value: _draft.telemetryEnabled,
                onChanged: (v) => setState(
                    () => _draft = _draft.copyWith(telemetryEnabled: v)),
              ),
              SwitchListTile(
                key: const Key('profile-scoring-toggle'),
                title: const Text('Scoring'),
                subtitle: const Text(
                  'Track per-round scorecards in the History tab.',
                ),
                value: _draft.scoringEnabled,
                onChanged: (v) => setState(
                    () => _draft = _draft.copyWith(scoringEnabled: v)),
              ),
              SwitchListTile(
                key: const Key('profile-beta-image-toggle'),
                title: const Text('Beta: image analysis'),
                subtitle: const Text(
                  'Upload a hole photo for the AI to analyze (paid tier).',
                ),
                value: _draft.betaImageAnalysisEnabled,
                onChanged: (v) => setState(
                  () => _draft = _draft.copyWith(betaImageAnalysisEnabled: v),
                ),
              ),
            ],
          ),
          // ── AI Provider card ────────────────────────────────────
          // Mirrors Android ApiSettingsScreen.kt (inline version)
          _ProfileCard(
            title: 'AI Provider',
            theme: theme,
            children: [
              _stringDropdown(
                key: const Key('profile-llm-provider'),
                label: 'LLM provider',
                value: _draft.llmProvider,
                options: const ['openAI', 'claude', 'gemini'],
                onChanged: (v) =>
                    setState(() => _draft = _draft.copyWith(llmProvider: v)),
              ),
              _stringDropdown(
                key: const Key('profile-tier'),
                label: 'Tier',
                value: _draft.userTier,
                options: const ['free', 'pro'],
                onChanged: (v) =>
                    setState(() => _draft = _draft.copyWith(userTier: v)),
              ),
            ],
          ),
          // ── API Keys card ───────────────────────────────────────
          // Mirrors Android ApiSettingsScreen.kt:83-109 and
          // iOS APISettingsView.swift:114-169 (inline version —
          // a future story can extract to a separate route)
          _ProfileCard(
            title: 'API Keys',
            theme: theme,
            subtitle: 'Stored securely in the platform Keychain '
                '(iOS) / EncryptedSharedPreferences (Android). '
                'Never appear in the profile blob.',
            children: [
              TextField(
                key: const Key('profile-openai-key-field'),
                controller: _openAiKeyController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'OpenAI API key',
                  border: OutlineInputBorder(),
                ),
              ),
              TextField(
                key: const Key('profile-claude-key-field'),
                controller: _claudeKeyController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Claude API key',
                  border: OutlineInputBorder(),
                ),
              ),
              TextField(
                key: const Key('profile-gemini-key-field'),
                controller: _geminiKeyController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Gemini API key',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          // ── Settings / Debug card ───────────────────────────────
          // Mirrors Android ProfileScreen.kt:212-244 and
          // iOS ProfileView.swift:105-124 (debug section only
          // in debug builds)
          if (_shouldShowDebugSection)
            _ProfileCard(
              title: 'Debug',
              theme: theme,
              subtitle: 'Visible in sideload builds only. Forces '
                  'the runtime tier to Pro so paid-tier code paths '
                  'can be exercised without a real purchase. '
                  'In-memory only.',
              children: [
                SwitchListTile(
                  key: const Key('profile-debug-force-pro'),
                  title: const Text('Force Pro tier'),
                  subtitle: Text(
                    'Effective tier: ${_isSubscribed ? 'Pro' : 'Free'}',
                    key: const Key('profile-debug-effective-tier'),
                  ),
                  value: widget.subscriptionService!.debugForcePro,
                  onChanged: (v) {
                    widget.subscriptionService!.debugForcePro = v;
                    setState(() {});
                  },
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _stringDropdown({
    required Key key,
    required String label,
    required String value,
    required List<String> options,
    required ValueChanged<String> onChanged,
  }) {
    final normalized = options.contains(value) ? value : options.first;
    return DropdownButtonFormField<String>(
      key: key,
      initialValue: normalized,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      items: options
          .map((o) => DropdownMenuItem<String>(
                value: o,
                child: Text(o),
              ))
          .toList(),
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }
}

/// Material 3 Card wrapper matching Android ProfileScreen.kt's
/// `ElevatedCard` sections. Title rendered in primary color
/// (titleSmall, semibold) with optional subtitle caption.
/// Children are separated by 12dp inside 16dp card padding.
class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.title,
    required this.theme,
    required this.children,
    this.subtitle,
  });

  final String title;
  final ThemeData theme;
  final List<Widget> children;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Card(
        elevation: 1,
        shape: RoundedCornerShape12._instance,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              for (int i = 0; i < children.length; i++) ...[
                children[i],
                if (i < children.length - 1) const SizedBox(height: 12),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Matches `CaddieShape.large` from the Android native.
class RoundedCornerShape12 {
  RoundedCornerShape12._();
  static final _instance = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(12),
  );
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.displayValue,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String displayValue;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label, style: theme.textTheme.bodyMedium),
            const Spacer(),
            Text(displayValue, style: theme.textTheme.bodyMedium),
          ],
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
        ),
      ],
    );
  }
}
