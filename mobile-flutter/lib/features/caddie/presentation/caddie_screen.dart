// CaddieScreen — KAN-281 (S11) flagship UX. The user enters a
// shot context (distance, lie, wind, slope, etc.), optionally
// dictates it via voice, and gets a deterministic baseline
// recommendation immediately followed by a streaming LLM
// commentary that the TTS engine reads aloud at the end.
//
// **Architecture: pure widget with injected dependencies.** The
// leaf widget takes:
//
//   - `engine`: a function `DeterministicAnalysis Function(ShotContext, ShotPreferences)`
//     so tests can substitute a mocked engine if needed (production
//     uses `GolfLogicEngine.analyze` directly via the page wrapper)
//   - `llmRouter`: an `LlmRouter` for the streaming commentary
//   - `sttService`: an `SttService` for voice input
//   - `ttsService`: a `TtsService` for the final TTS playback
//   - `logger`: the canonical `LoggingService`
//   - `profile`: the player's `ShotPreferences` (loaded from
//     `ProfileRepository` in the page wrapper)
//
// Every dependency is constructor-injected → fully unit-testable
// without standing up the global `logger` singleton, the real
// LLM router, or the platform speech engines. The page wrapper
// (`caddie_page.dart`) wires the production instances.
//
// **State machine** (`_CaddieFlowStage`):
//
//   idle → editing → engineDone → streamingLlm → speaking → done
//
// At each stage the screen renders a different body:
//
//   - idle / editing: ShotInputForm + (optional) voice button
//   - engineDone: ExecutionPlan + DeterministicAnalysis card,
//     "Ask AI for commentary" CTA
//   - streamingLlm: live token-by-token rendering of the LLM
//     stream while the deterministic card stays visible above
//   - speaking: "Speaking..." indicator with a "Stop" button
//   - done: full transcript + replay button
//
// **C-3 compliance:** every latency claim is measured via the
// canonical CloudWatch event names — `llm_latency` (already
// emitted by `LlmRouter`), `tts_latency` (emitted by
// `FlutterTtsService` via `TtsLatencyTracker`), `stt_latency`
// (emitted by `SpeechToTextService`). The screen does NOT
// measure with Flutter frame timings.

import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';

import '../../../core/golf/golf_enums.dart';
import '../../../core/golf/golf_logic_engine.dart';
import '../../../core/golf/shot_context.dart';
import '../../../core/golf/target_strategy.dart';
import '../../../core/icons/caddie_icons.dart';
import '../../../core/llm/llm_messages.dart';
import '../../../core/llm/llm_router.dart';
import '../../../core/logging/log_event.dart';
import '../../../core/logging/logging_service.dart';
import '../../../core/voice/stt_service.dart';
import '../../../core/voice/tts_service.dart';
import '../../../core/voice/voice_input_parser.dart';
import '../../../core/voice/voice_settings.dart';

/// State the screen is in. Drives the body rendering.
enum CaddieFlowStage {
  /// User is editing the shot context. No recommendation yet.
  editing,

  /// `GolfLogicEngine.analyze` has produced a deterministic
  /// recommendation. The card is visible. The "Ask AI" button
  /// is now enabled.
  engineDone,

  /// LLM router is streaming a token-by-token commentary. The
  /// deterministic card is still visible above the live stream.
  streamingLlm,

  /// LLM stream completed; TTS is reading the final commentary
  /// out loud. A "Stop" button is visible.
  speaking,

  /// Full flow complete. Final transcript + "Replay" button.
  done,
}

class CaddieScreen extends StatefulWidget {
  const CaddieScreen({
    super.key,
    required this.profile,
    required this.llmRouter,
    required this.sttService,
    required this.ttsService,
    required this.logger,
    this.preferredProvider = LlmProviderId.openAi,
    this.tier = LlmTier.free,
    this.persona = CaddieVoicePersona.defaultPersona,
    this.engine = _defaultEngine,
    this.initialContext = const ShotContext(),
  });

  /// The player's bag + tendencies + preferences. Loaded from
  /// `ProfileRepository` in the page wrapper.
  final ShotPreferences profile;

  final LlmRouter llmRouter;
  final SttService sttService;
  final TtsService ttsService;
  final LoggingService logger;

  /// Provider routing for the LLM call. Pulled from
  /// `PlayerProfile.llmProvider` in the page wrapper.
  final LlmProviderId preferredProvider;

  /// Tier for the LLM call. Free → user's API key, paid → proxy.
  final LlmTier tier;

  /// Voice persona for the TTS playback at the end of the flow.
  final CaddieVoicePersona persona;

  /// Engine override for tests. Production uses
  /// `GolfLogicEngine.analyze`.
  final DeterministicAnalysis Function(
    ShotContext context,
    ShotPreferences profile,
  ) engine;

  /// Optional pre-populated context (e.g. when the user navigates
  /// here from the map screen with a hole already selected).
  final ShotContext initialContext;

  @override
  State<CaddieScreen> createState() => _CaddieScreenState();
}

DeterministicAnalysis _defaultEngine(
  ShotContext context,
  ShotPreferences profile,
) =>
    GolfLogicEngine.analyze(context: context, profile: profile);

class _CaddieScreenState extends State<CaddieScreen> {
  late ShotContext _context = widget.initialContext;
  CaddieFlowStage _stage = CaddieFlowStage.editing;

  // Voice input state
  bool _isListening = false;
  String _voiceTranscript = '';
  StreamSubscription<SttEvent>? _sttSub;

  // Engine + LLM result state
  DeterministicAnalysis? _analysis;
  final StringBuffer _llmTranscript = StringBuffer();
  StreamSubscription<String>? _llmSub;
  String? _llmError;
  int? _llmLatencyMs;

  // TTS state
  StreamSubscription<bool>? _ttsSpeakingSub;
  bool _ttsActive = false;

  @override
  void initState() {
    super.initState();
    _ttsService.initialize();
    _ttsSpeakingSub = _ttsService.isSpeakingStream.listen((speaking) {
      if (!mounted) return;
      setState(() => _ttsActive = speaking);
      if (!speaking && _stage == CaddieFlowStage.speaking) {
        setState(() => _stage = CaddieFlowStage.done);
      }
    });
  }

  TtsService get _ttsService => widget.ttsService;

  @override
  void dispose() {
    _sttSub?.cancel();
    _llmSub?.cancel();
    _ttsSpeakingSub?.cancel();
    super.dispose();
  }

  // ── voice input ─────────────────────────────────────────────────

  Future<void> _startVoice() async {
    if (_isListening) return;
    final granted = await widget.sttService.requestPermission();
    if (!granted || !mounted) return;
    setState(() {
      _isListening = true;
      _voiceTranscript = '';
    });
    _sttSub = widget.sttService.startListening().listen(
      (event) {
        if (!mounted) return;
        if (event is SttPartialEvent) {
          setState(() => _voiceTranscript = event.text);
        } else if (event is SttFinalTranscriptEvent) {
          setState(() {
            _voiceTranscript = event.text;
            _isListening = false;
          });
          _applyVoiceTranscript(event.text);
        } else if (event is SttErrorEvent) {
          setState(() {
            _isListening = false;
          });
        }
      },
      onDone: () {
        if (mounted) setState(() => _isListening = false);
      },
    );
  }

  void _stopVoice() {
    widget.sttService.stop();
    _sttSub?.cancel();
    if (mounted) setState(() => _isListening = false);
  }

  void _applyVoiceTranscript(String transcript) {
    final parsed = VoiceInputParser.parse(transcript);
    final applied =
        VoiceInputParser.apply(result: parsed, into: _context);
    setState(() => _context = applied.context);
  }

  // ── recommendation flow ─────────────────────────────────────────

  void _runEngine() {
    final analysis = widget.engine(_context, widget.profile);
    setState(() {
      _analysis = analysis;
      _stage = CaddieFlowStage.engineDone;
      _llmTranscript.clear();
      _llmError = null;
    });
  }

  Future<void> _streamLlmCommentary() async {
    final analysis = _analysis;
    if (analysis == null) return;

    setState(() {
      _stage = CaddieFlowStage.streamingLlm;
      _llmTranscript.clear();
      _llmError = null;
      _llmLatencyMs = null;
    });

    final request = _buildLlmRequest(analysis);
    final stopwatch = Stopwatch()..start();
    try {
      _llmSub = widget.llmRouter
          .chatCompletionStream(
        request: request,
        tier: widget.tier,
        preferredProvider: widget.preferredProvider,
      )
          .listen(
        (chunk) {
          if (!mounted) return;
          if (_llmLatencyMs == null) {
            _llmLatencyMs = stopwatch.elapsedMilliseconds;
          }
          setState(() => _llmTranscript.write(chunk));
        },
        onError: (Object error) {
          stopwatch.stop();
          // ignore: avoid_print
          print('LLM STREAM ERROR: $error');
          if (!mounted) return;
          setState(() {
            _llmError = '$error';
            _stage = CaddieFlowStage.engineDone;
          });
        },
        onDone: () {
          stopwatch.stop();
          _llmLatencyMs ??= stopwatch.elapsedMilliseconds;
          if (!mounted) return;
          final fullText = _llmTranscript.toString();
          if (fullText.isEmpty) {
            setState(() => _stage = CaddieFlowStage.engineDone);
            return;
          }
          setState(() => _stage = CaddieFlowStage.done);
        },
      );
    } catch (e, stackTrace) {
      stopwatch.stop();
      // ignore: avoid_print
      print('LLM CALL ERROR: $e');
      // ignore: avoid_print
      print('STACK TRACE: $stackTrace');
      if (!mounted) return;
      setState(() {
        _llmError = '$e';
        _stage = CaddieFlowStage.engineDone;
      });
    }
  }

  LlmRequest _buildLlmRequest(DeterministicAnalysis analysis) {
    final ctx = _context;
    const systemPrompt =
        'You are a calm, expert golf caddie. Given the deterministic '
        "shot analysis below, give the player a 2-3 sentence commentary "
        'explaining why this club + target makes sense. Speak directly '
        "to the player. Don't repeat the numbers — interpret them.";
    final userPrompt = StringBuffer()
      ..writeln('Distance: ${ctx.distanceYards} yards')
      ..writeln('Lie: ${ctx.lieType.displayName}')
      ..writeln('Wind: ${ctx.windStrength.name} ${ctx.windDirection.displayName}')
      ..writeln('Slope: ${ctx.slope.displayName}')
      ..writeln('Effective distance: ${analysis.effectiveDistanceYards} yards')
      ..writeln('Recommended club: ${analysis.recommendedClub.displayName}')
      ..writeln('Target: ${analysis.targetStrategy.target}')
      ..writeln('Preferred miss: ${analysis.targetStrategy.preferredMiss}');
    return LlmRequest(
      messages: [
        const LlmMessage(role: 'system', content: systemPrompt),
        LlmMessage(role: 'user', content: userPrompt.toString()),
      ],
    );
  }

  Future<void> _stopSpeaking() async {
    await widget.ttsService.stop();
    if (!mounted) return;
    setState(() => _stage = CaddieFlowStage.done);
  }

  void _resetFlow() {
    setState(() {
      _stage = CaddieFlowStage.editing;
      _analysis = null;
      _llmTranscript.clear();
      _llmError = null;
    });
  }

  // ── build ───────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Caddie'),
        leading: Padding(
          padding: const EdgeInsets.all(8),
          child: CaddieIcons.golfer(
            size: 24,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ShotInputForm(
              context: _context,
              onChanged: (c) => setState(() => _context = c),
            ),
            const SizedBox(height: 12),
            VoiceInputControl(
              isListening: _isListening,
              transcript: _voiceTranscript,
              onStart: _startVoice,
              onStop: _stopVoice,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _stage == CaddieFlowStage.streamingLlm ||
                      _stage == CaddieFlowStage.speaking
                  ? null
                  : _runEngine,
              icon: CaddieIcons.target(size: 18),
              label: const Text('Get recommendation'),
            ),
            const SizedBox(height: 16),
            if (_analysis != null)
              RecommendationCard(
                analysis: _analysis!,
                stage: _stage,
                llmTranscript: _llmTranscript.toString(),
                llmError: _llmError,
                ttsActive: _ttsActive,
                llmLatencyMs: _llmLatencyMs,
                onAskAi: _streamLlmCommentary,
                onStopSpeaking: _stopSpeaking,
                onResetFlow: _resetFlow,
                onListenPressed: (text) async {
                  setState(() => _stage = CaddieFlowStage.speaking);
                  await widget.ttsService.speak(text, persona: widget.persona);
                },
              ),
          ],
        ),
      ),
    );
  }
}

// ── ShotInputForm ──────────────────────────────────────────────────

/// Compact form for editing a `ShotContext`. Pulled out as its
/// own widget so the caddie screen test can verify it independently
/// of the rest of the flow.
class ShotInputForm extends StatelessWidget {
  const ShotInputForm({
    super.key,
    required this.context,
    required this.onChanged,
  });

  // ignore: avoid_renaming_method_parameters
  final ShotContext context;
  final ValueChanged<ShotContext> onChanged;

  @override
  Widget build(BuildContext buildCtx) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Shot context',
                style: Theme.of(buildCtx).textTheme.titleMedium),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('caddie-distance-field'),
              initialValue: '${context.distanceYards}',
              decoration: const InputDecoration(
                labelText: 'Distance (yards)',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              onChanged: (v) {
                final parsed = int.tryParse(v.trim());
                if (parsed != null) {
                  onChanged(context.copyWith(distanceYards: parsed));
                }
              },
            ),
            const SizedBox(height: 12),
            _enumDropdown<ShotType>(
              label: 'Shot type',
              value: context.shotType,
              values: ShotType.values,
              onChanged: (v) => onChanged(context.copyWith(shotType: v)),
              displayName: (v) => v.displayName,
            ),
            const SizedBox(height: 12),
            _enumDropdown<LieType>(
              label: 'Lie',
              value: context.lieType,
              values: LieType.values,
              onChanged: (v) => onChanged(context.copyWith(lieType: v)),
              displayName: (v) => v.displayName,
            ),
            const SizedBox(height: 12),
            _enumDropdown<WindStrength>(
              label: 'Wind strength',
              value: context.windStrength,
              values: WindStrength.values,
              onChanged: (v) =>
                  onChanged(context.copyWith(windStrength: v)),
              displayName: (v) => v.displayName,
            ),
            const SizedBox(height: 12),
            _enumDropdown<WindDirection>(
              label: 'Wind direction',
              value: context.windDirection,
              values: WindDirection.values,
              onChanged: (v) =>
                  onChanged(context.copyWith(windDirection: v)),
              displayName: (v) => v.displayName,
            ),
            const SizedBox(height: 12),
            _enumDropdown<Slope>(
              label: 'Slope',
              value: context.slope,
              values: Slope.values,
              onChanged: (v) => onChanged(context.copyWith(slope: v)),
              displayName: (v) => v.displayName,
            ),
          ],
        ),
      ),
    );
  }

  Widget _enumDropdown<T extends Enum>({
    required String label,
    required T value,
    required List<T> values,
    required ValueChanged<T> onChanged,
    String Function(T)? displayName,
  }) {
    return DropdownButtonFormField<T>(
      key: Key('caddie-${label.toLowerCase().replaceAll(' ', '-')}'),
      initialValue: value,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      items: values
          .map((v) => DropdownMenuItem<T>(
                value: v,
                child: Text(displayName?.call(v) ?? v.name),
              ))
          .toList(),
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }
}

// ── VoiceInputControl ──────────────────────────────────────────────

/// Mic button + live partial transcript. Stateless — the parent
/// owns the listening state.
class VoiceInputControl extends StatelessWidget {
  const VoiceInputControl({
    super.key,
    required this.isListening,
    required this.transcript,
    required this.onStart,
    required this.onStop,
  });

  final bool isListening;
  final String transcript;
  final VoidCallback onStart;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                FilledButton.tonalIcon(
                  key: const Key('caddie-voice-button'),
                  onPressed: isListening ? onStop : onStart,
                  icon: isListening ? const Icon(Icons.stop) : CaddieIcons.mic(),
                  label: Text(isListening ? 'Stop' : 'Speak shot details'),
                ),
                const Spacer(),
                if (isListening)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            if (transcript.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                transcript,
                key: const Key('caddie-voice-transcript'),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── RecommendationCard ─────────────────────────────────────────────

/// Renders the deterministic engine output, the streaming LLM
/// commentary, and the per-stage CTAs (ask AI / stop speaking /
/// replay).
class RecommendationCard extends StatelessWidget {
  const RecommendationCard({
    super.key,
    required this.analysis,
    required this.stage,
    required this.llmTranscript,
    required this.llmError,
    required this.ttsActive,
    required this.onAskAi,
    required this.onStopSpeaking,
    required this.onResetFlow,
    this.onListenPressed,
    this.llmLatencyMs,
  });

  final DeterministicAnalysis analysis;
  final CaddieFlowStage stage;
  final String llmTranscript;
  final String? llmError;
  final bool ttsActive;
  final int? llmLatencyMs;
  final VoidCallback onAskAi;
  final VoidCallback onStopSpeaking;
  final VoidCallback onResetFlow;
  final void Function(String text)? onListenPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      key: const Key('caddie-recommendation-card'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Recommendation',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            _row('Effective distance',
                '${analysis.effectiveDistanceYards} yards'),
            _row('Club', analysis.recommendedClub.displayName),
            if (analysis.alternateClub != null)
              _row('Alternate', analysis.alternateClub!.displayName),
            const SizedBox(height: 8),
            Text(
              analysis.targetStrategy.target,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 4),
            Text(
              analysis.targetStrategy.preferredMiss,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 8),
            if (stage == CaddieFlowStage.engineDone && llmError == null)
              FilledButton.icon(
                key: const Key('caddie-ask-ai-button'),
                onPressed: onAskAi,
                icon: CaddieIcons.target(),
                label: const Text('Ask AI for commentary'),
              ),
            if (llmError != null) ...[
              Text(
                'AI commentary failed: $llmError',
                key: const Key('caddie-llm-error'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: onAskAi,
                child: const Text('Retry'),
              ),
            ],
            if (stage == CaddieFlowStage.streamingLlm) ...[
              Row(
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'AI commentary streaming…',
                    style: theme.textTheme.bodySmall,
                  ),
                  if (kDebugMode && llmLatencyMs != null) ...[
                    const Spacer(),
                    Text(
                      '${llmLatencyMs}ms',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                        fontFamily: 'monospace',
                        fontSize: 11,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              Text(
                llmTranscript,
                key: const Key('caddie-llm-transcript'),
                style: theme.textTheme.bodyMedium,
              ),
            ],
            if (stage == CaddieFlowStage.speaking) ...[
              Row(
                children: [
                  CaddieIcons.listen(color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    ttsActive ? 'Speaking…' : 'Preparing…',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const Spacer(),
                  TextButton.icon(
                    key: const Key('caddie-stop-speaking-button'),
                    onPressed: onStopSpeaking,
                    icon: CaddieIcons.close(size: 18),
                    label: const Text('Stop'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                llmTranscript,
                style: theme.textTheme.bodyMedium,
              ),
            ],
            if (stage == CaddieFlowStage.done) ...[
              if (kDebugMode && llmLatencyMs != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    'LLM: ${llmLatencyMs}ms to first token',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                      fontFamily: 'monospace',
                      fontSize: 11,
                    ),
                  ),
                ),
              Text(
                llmTranscript,
                key: const Key('caddie-final-transcript'),
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  if (llmTranscript.isNotEmpty)
                    OutlinedButton.icon(
                      key: const Key('caddie-listen-button'),
                      onPressed: () async {
                        onListenPressed?.call(llmTranscript);
                      },
                      icon: CaddieIcons.listen(size: 18),
                      label: const Text('Listen'),
                    ),
                  if (llmTranscript.isNotEmpty) const SizedBox(width: 8),
                  OutlinedButton.icon(
                    key: const Key('caddie-reset-button'),
                    onPressed: onResetFlow,
                    icon: CaddieIcons.refresh(),
                    label: const Text('New shot'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 140,
            child: Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          ),
          Text(value),
        ],
      ),
    );
  }
}
