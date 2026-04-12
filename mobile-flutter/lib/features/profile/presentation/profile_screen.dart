// ProfileScreen — KAN-283 (S13), restructured to match the iOS
// ProfileView.swift and Android ProfileScreen.kt card-based layout.
//
// **Architecture: pure widget with constructor injection.** The
// page wrapper does the I/O; the leaf widget is a pure form.
//
// **Structure (mirrors iOS ProfileView.swift:18-132 exactly):**
//   Card: Player Info — handicap, miss tendency, aggressiveness
//   Card: Caddie Voice & Personality — accent, gender, personality
//   Nav links: Your Bag, Swing Info, Tee Box Preference
//   Card: Features — scoring toggle, image analysis toggle (paid)
//   Card: Settings — API Settings (inline), debug toggle (debug only)
//   Nav link: Contact Info
//
// **Critical safety invariant:** API keys are entered via this
// screen but **never appear on the `PlayerProfile` model**.

import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';

import '../../../core/icons/caddie_icons.dart';
import '../../../core/monetization/subscription_service.dart';
import '../../../core/storage/secure_keys_storage.dart';
import '../../../models/player_profile.dart';
import 'contact_info_screen.dart';
import 'swing_info_screen.dart';
import 'tee_box_preference_screen.dart';
import 'your_bag_screen.dart';

/// One round-trippable bundle of changes the user can save.
class ProfileSaveRequest {
  const ProfileSaveRequest({
    required this.profile,
    required this.secrets,
  });

  final PlayerProfile profile;
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
  final Map<String, String> initialSecrets;
  final SubscriptionService? subscriptionService;
  final bool showDebugSection;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late PlayerProfile _draft = widget.profile;

  // API key controllers — values land in secure storage on save.
  late final TextEditingController _openAiKeyController =
      TextEditingController(text: widget.initialSecrets[SecureKey.openAi] ?? '');
  late final TextEditingController _claudeKeyController =
      TextEditingController(text: widget.initialSecrets[SecureKey.claude] ?? '');
  late final TextEditingController _geminiKeyController =
      TextEditingController(text: widget.initialSecrets[SecureKey.gemini] ?? '');

  bool _saving = false;

  // KAN-95 debug section state.
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
    _openAiKeyController.dispose();
    _claudeKeyController.dispose();
    _geminiKeyController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final request = ProfileSaveRequest(
      profile: _draft,
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

  // ── sub-screen navigation helpers ──────────────────────────────

  Future<void> _pushSubScreen(Widget screen) async {
    final result = await Navigator.push<PlayerProfile>(
      context,
      MaterialPageRoute(builder: (_) => screen),
    );
    if (result != null && mounted) {
      setState(() => _draft = result);
    }
  }

  // ── build ──────────────────────────────────────────────────────

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
          // ── Section 1: Player Info ──────────────────────────────
          // iOS ProfileView.swift:18-37
          _ProfileCard(
            title: 'Player Info',
            theme: theme,
            children: [
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
                key: const Key('profile-miss-tendency'),
                label: 'Miss Tendency',
                value: _draft.missTendency,
                options: const ['none', 'left', 'right', 'thin', 'fat'],
                onChanged: (v) =>
                    setState(() => _draft = _draft.copyWith(missTendency: v)),
              ),
              _stringDropdown(
                key: const Key('profile-aggressiveness'),
                label: 'Default Aggressiveness',
                value: _draft.aggressiveness,
                options: const ['conservative', 'normal', 'aggressive'],
                onChanged: (v) =>
                    setState(() => _draft = _draft.copyWith(aggressiveness: v)),
              ),
            ],
          ),
          // ── Section 2: Caddie Voice & Personality ───────────────
          // iOS ProfileView.swift:39-61
          _ProfileCard(
            title: 'Caddie Voice & Personality',
            theme: theme,
            children: [
              _stringDropdown(
                key: const Key('profile-voice-accent'),
                label: 'Accent',
                value: _draft.caddieVoiceAccent,
                options: const ['american', 'british', 'australian', 'indian'],
                onChanged: (v) => setState(
                  () => _draft = _draft.copyWith(caddieVoiceAccent: v),
                ),
              ),
              _stringDropdown(
                key: const Key('profile-voice-gender'),
                label: 'Gender',
                value: _draft.caddieVoiceGender,
                options: const ['male', 'female'],
                onChanged: (v) => setState(
                  () => _draft = _draft.copyWith(caddieVoiceGender: v),
                ),
              ),
              _stringDropdown(
                key: const Key('profile-persona'),
                label: 'Personality',
                value: _draft.caddiePersona,
                options: const [
                  'professional',
                  'supportiveGrandparent',
                  'collegeBuddy',
                  'drillSergeant',
                  'chillSurfer',
                ],
                onChanged: (v) => setState(
                  () => _draft = _draft.copyWith(caddiePersona: v),
                ),
              ),
            ],
          ),
          // ── Section 3: Navigation links ─────────────────────────
          // iOS ProfileView.swift:63-86
          _NavLinkRow(
            icon: Icons.shopping_bag_outlined,
            title: 'Your Bag',
            subtitle: '${_draft.clubDistances.length}/13 clubs',
            onTap: () => _pushSubScreen(YourBagScreen(profile: _draft)),
          ),
          _NavLinkRow(
            icon: Icons.sports_golf_outlined,
            title: 'Swing Info',
            subtitle: 'Shape, tendencies, short game',
            onTap: () => _pushSubScreen(SwingInfoScreen(profile: _draft)),
          ),
          _NavLinkRow(
            icon: Icons.flag_outlined,
            title: 'Tee Box Preference',
            subtitle: _teeBoxDisplayName(_draft.preferredTeeBox),
            onTap: () => _pushSubScreen(
                TeeBoxPreferenceScreen(profile: _draft)),
          ),
          const SizedBox(height: 8),
          // ── Section 4: Features ─────────────────────────────────
          // iOS ProfileView.swift:88-103
          _ProfileCard(
            title: 'Features',
            theme: theme,
            children: [
              SwitchListTile(
                key: const Key('profile-scoring-toggle'),
                title: const Text('Enable Scorecard'),
                value: _draft.scoringEnabled,
                onChanged: (v) => setState(
                    () => _draft = _draft.copyWith(scoringEnabled: v)),
              ),
              if (_draft.scoringEnabled &&
                  _draft.email.isEmpty &&
                  _draft.phone.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline,
                          size: 16, color: theme.colorScheme.outline),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Add a phone or email in Contact Info to identify '
                          'your scorecards.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              if (_isSubscribed)
                SwitchListTile(
                  key: const Key('profile-beta-image-toggle'),
                  title: const Text('Image Analysis (BETA)'),
                  subtitle: const Text(
                    'Attach a photo of your lie for AI analysis.',
                  ),
                  value: _draft.betaImageAnalysisEnabled,
                  onChanged: (v) => setState(
                    () => _draft = _draft.copyWith(betaImageAnalysisEnabled: v),
                  ),
                ),
            ],
          ),
          // ── Section 5: Settings ─────────────────────────────────
          // iOS ProfileView.swift:105-124
          _ProfileCard(
            title: 'Settings',
            theme: theme,
            children: [
              // AI Provider + keys inline (a future story can
              // extract to a separate route matching iOS/Android)
              _stringDropdown(
                key: const Key('profile-llm-provider'),
                label: 'AI Provider',
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
              SwitchListTile(
                key: const Key('profile-telemetry-toggle'),
                title: const Text('Share Usage Data'),
                subtitle: const Text(
                  'Sends anonymous usage stats to help improve CaddieAI.',
                ),
                value: _draft.telemetryEnabled,
                onChanged: (v) => setState(
                    () => _draft = _draft.copyWith(telemetryEnabled: v)),
              ),
              if (_shouldShowDebugSection) ...[
                const Divider(),
                Text(
                  'Debug',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
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
            ],
          ),
          // ── Section 5b: API Keys card ──────────────────────────
          _ProfileCard(
            title: 'API Keys',
            theme: theme,
            subtitle: 'Stored in platform Keychain / '
                'EncryptedSharedPreferences.',
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
          // ── Section 6: Contact Info ─────────────────────────────
          // iOS ProfileView.swift:126-132
          _NavLinkRow(
            icon: Icons.email_outlined,
            title: 'Contact Info',
            subtitle: _draft.name.isNotEmpty
                ? _draft.name
                : 'Send feedback or set up your info',
            onTap: () =>
                _pushSubScreen(ContactInfoScreen(profile: _draft)),
          ),
          const SizedBox(height: 24),
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
                child: Text(_displayName(o)),
              ))
          .toList(),
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }

  static String _displayName(String raw) {
    // camelCase → Title Case with spaces
    return raw
        .replaceAllMapped(
          RegExp(r'([a-z])([A-Z])'),
          (m) => '${m[1]} ${m[2]}',
        )
        .replaceFirst(raw[0], raw[0].toUpperCase());
  }

  static String _teeBoxDisplayName(String value) {
    switch (value) {
      case 'championship':
        return 'Black / Championship';
      case 'blue':
        return 'Blue';
      case 'white':
        return 'White';
      case 'senior':
        return 'Gold / Silver';
      case 'forward':
        return 'Red / Forward';
      default:
        return value;
    }
  }
}

// ── presentational sub-widgets ─────────────────────────────────────

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
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
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

/// Navigation link row matching iOS NavigationLink with icon +
/// title + subtitle + trailing chevron, and Android NavLinkRow
/// (ProfileScreen.kt:263-299).
class _NavLinkRow extends StatelessWidget {
  const _NavLinkRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        child: ListTile(
          leading: Icon(icon, size: 28, color: theme.colorScheme.primary),
          title: Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          subtitle: Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: onTap,
        ),
      ),
    );
  }
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
