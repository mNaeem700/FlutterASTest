import 'dart:io';

import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../llm/llm_settings.dart';

/// What the LLM is shown about the screen under test (Doc 16.6, 16.8).
enum ContextMode {
  /// Group C/D: context selected from the Program Knowledge Graph.
  pkg,

  /// Group A: the raw source file of the screen.
  baseline,

  /// Group B / Baseline 3: the screen file and the project files it imports.
  file,

  /// Baseline 4: every Dart file under lib/.
  repository,
}

/// A component removed for the ablation study (Doc 16.11). A3, removing
/// reflection, is a run without `reflect`.
enum Ablation {
  none,

  /// A1: no PKG relationships; only each screen's local structure remains.
  noPkgLinks,

  /// A2: no Context Builder selection, scoring, pruning or compression.
  noContextBuilder,

  /// A4: no structured prompt; only a one-line task and the context.
  noPromptBuilder,

  /// A5: reflection repairs failures but ignores coverage gaps.
  noCoverageGuidance,
}

/// Settings of one experiment run. Every run writes into its own folder, so
/// runs of different modes on the same project can be compared afterwards.
@immutable
class ExperimentConfig {
  const ExperimentConfig({
    this.mode = ContextMode.pkg,
    this.reflect = false,
    this.maxIterations = defaultMaxIterations,
    this.testTimeout = const Duration(minutes: 10),
    this.ablation = Ablation.none,
    this.tokenBudget = 8000,
    this.flakyRetries = 2,
    this.targetLineCoverage = 0.9,
    this.targetBranchCoverage = 0.8,
    this.minimumImprovement = 0.02,
    this.label,
    this.model,
    this.outputRoot,
    this.installTests = false,
    this.resume = false,
    this.provider = 'local',
    this.llm = const LlmSettings(),
    this.mutation = false,
    this.maxMutants = 20,
    this.screens = const {},
    this.maxScreens,
    this.requestInterval,
  });

  /// Upper bound of repair iterations of the reflection loop (Doc 15.20.3).
  static const defaultMaxIterations = 5;

  final ContextMode mode;

  /// Repair failing tests by feeding the run result back to the LLM.
  final bool reflect;
  final int maxIterations;

  /// A `flutter test` run that takes longer is killed and counted as failed.
  final Duration testTimeout;
  final Ablation ablation;

  /// Context size limit in estimated tokens (Doc 10.19.1).
  final int tokenBudget;

  /// Extra runs of a failing test file, to tell flaky tests from failing ones.
  final int flakyRetries;

  /// Reflection stops improving a passing file at this line coverage.
  final double targetLineCoverage;
  final double targetBranchCoverage;

  /// Reflection stops when an iteration improves less than this.
  final double minimumImprovement;

  /// Suffix separating repetitions of the same setup, e.g. `rep2`.
  final String? label;

  /// LLM model id; null uses the service's default.
  final String? model;

  /// Where results go; null means `.flutterastest/` in the target project.
  final String? outputRoot;

  /// Copy passing tests into the target project's `test/flutterastest/`.
  final bool installTests;

  /// Replay saved LLM replies, so an interrupted run repeats no call.
  final bool resume;

  /// `local` (a model on this machine, the default), `gemini` or `openai`.
  final String provider;
  final LlmSettings llm;

  /// Measure each passing test file with mutation testing; slow.
  final bool mutation;
  final int maxMutants;

  /// Only these screens; empty means all.
  final Set<String> screens;

  /// Evenly spaced sample of this many screens, to stay within a quota. The
  /// same screens are chosen in every mode, so runs stay comparable.
  final int? maxScreens;

  /// Pause between LLM calls; null means 10 s, or none for a local model.
  final Duration? requestInterval;

  /// A developer's run keeps everything in their project. With an explicit
  /// output folder (research runs) the target project stays unchanged.
  ExperimentConfig resolvedFor(String projectPath) => outputRoot != null
      ? this
      : copyWith(outputRoot: p.join(projectPath, '.flutterastest'), installTests: true);

  String get analysisDirectory => p.join(outputRoot ?? 'output', 'analysis');

  /// `pkg`, `baseline-reflect`, `pkg-reflect-noCoverageGuidance-rep2`, ...
  String get runName => [
        mode.name,
        if (reflect) 'reflect',
        if (ablation != Ablation.none) ablation.name,
        if (label != null) label!,
      ].join('-');

  String get runDirectory => p.join(outputRoot ?? 'output', 'runs', runName);

  String get contextTitle => switch (mode) {
        ContextMode.pkg => 'Screen context (from the Program Knowledge Graph)',
        ContextMode.baseline => 'Screen source code',
        ContextMode.file => 'Relevant source files',
        ContextMode.repository => 'Repository source code',
      };

  bool get coverageGuided => reflect && ablation != Ablation.noCoverageGuidance;

  ExperimentConfig copyWith({
    ContextMode? mode,
    bool? reflect,
    int? maxIterations,
    Duration? testTimeout,
    Ablation? ablation,
    int? tokenBudget,
    int? flakyRetries,
    String? label,
    String? model,
    String? outputRoot,
    bool? installTests,
    bool? resume,
    String? provider,
    LlmSettings? llm,
    bool? mutation,
    int? maxMutants,
    Set<String>? screens,
    int? maxScreens,
    Duration? requestInterval,
  }) =>
      ExperimentConfig(
        mode: mode ?? this.mode,
        reflect: reflect ?? this.reflect,
        maxIterations: maxIterations ?? this.maxIterations,
        testTimeout: testTimeout ?? this.testTimeout,
        ablation: ablation ?? this.ablation,
        tokenBudget: tokenBudget ?? this.tokenBudget,
        flakyRetries: flakyRetries ?? this.flakyRetries,
        targetLineCoverage: targetLineCoverage,
        targetBranchCoverage: targetBranchCoverage,
        minimumImprovement: minimumImprovement,
        label: label ?? this.label,
        model: model ?? this.model,
        outputRoot: outputRoot ?? this.outputRoot,
        installTests: installTests ?? this.installTests,
        resume: resume ?? this.resume,
        provider: provider ?? this.provider,
        llm: llm ?? this.llm,
        mutation: mutation ?? this.mutation,
        maxMutants: maxMutants ?? this.maxMutants,
        screens: screens ?? this.screens,
        maxScreens: maxScreens ?? this.maxScreens,
        requestInterval: requestInterval ?? this.requestInterval,
      );

  /// Reads the YAML configuration file of Doc 17.10. Missing keys keep their
  /// defaults.
  factory ExperimentConfig.fromYaml(String path) {
    final yaml = loadYaml(File(path).readAsStringSync());
    if (yaml is! YamlMap) return const ExperimentConfig();
    final reflection = yaml['reflection'];
    final llm = yaml['llm'];
    final context = yaml['context'];
    final execution = yaml['execution'];
    Object? read(Object? section, String key) => section is YamlMap ? section[key] : null;

    return ExperimentConfig(
      mode: ContextMode.values.byName('${yaml['mode'] ?? 'pkg'}'),
      ablation: Ablation.values.byName('${yaml['ablation'] ?? 'none'}'),
      label: yaml['label'] as String?,
      reflect: read(reflection, 'enabled') as bool? ?? false,
      maxIterations: read(reflection, 'maxIterations') as int? ?? defaultMaxIterations,
      targetLineCoverage: (read(reflection, 'targetLineCoverage') as num?)?.toDouble() ?? 0.9,
      targetBranchCoverage: (read(reflection, 'targetBranchCoverage') as num?)?.toDouble() ?? 0.8,
      minimumImprovement: (read(reflection, 'minimumImprovement') as num?)?.toDouble() ?? 0.02,
      model: read(llm, 'model') as String?,
      provider: read(llm, 'provider') as String? ?? 'local',
      llm: LlmSettings(
        temperature: (read(llm, 'temperature') as num?)?.toDouble(),
        topP: (read(llm, 'topP') as num?)?.toDouble(),
        seed: read(llm, 'seed') as int?,
        maxOutputTokens: read(llm, 'maxOutputTokens') as int?,
        requestTimeout: read(llm, 'timeoutSeconds') == null
            ? null
            : Duration(seconds: read(llm, 'timeoutSeconds') as int),
      ),
      mutation: read(yaml['mutation'], 'enabled') as bool? ?? false,
      maxMutants: read(yaml['mutation'], 'maxMutants') as int? ?? 20,
      tokenBudget: read(context, 'tokenBudget') as int? ?? 8000,
      testTimeout: Duration(seconds: read(execution, 'testTimeoutSeconds') as int? ?? 600),
      flakyRetries: read(execution, 'flakyRetries') as int? ?? 2,
    );
  }

  Map<String, dynamic> toJson() => {
        'mode': mode.name,
        'ablation': ablation.name,
        'reflect': reflect,
        'maxIterations': reflect ? maxIterations : 0,
        'testTimeoutSeconds': testTimeout.inSeconds,
        'tokenBudget': tokenBudget,
        'flakyRetries': flakyRetries,
        'targetLineCoverage': targetLineCoverage,
        'targetBranchCoverage': targetBranchCoverage,
        'minimumImprovement': minimumImprovement,
        'label': label,
        'provider': provider,
        'llmSettings': llm.toJson(),
        'mutation': mutation,
        'maxMutants': maxMutants,
        if (screens.isNotEmpty) 'screens': screens.toList(),
        'maxScreens': maxScreens,
        'installTests': installTests,
      };
}
