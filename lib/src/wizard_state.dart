import 'dart:async';

import 'package:signals_flutter/signals_flutter.dart';

import 'wizard_step.dart';

/// A wizard's state: which step is on screen, which steps are done or
/// skipped, whether a save runs, and the overview and summary around the
/// steps. Pure signals, no widgets: the app draws it and calls [next],
/// [skip], [back], [goTo], [begin] and [complete].
///
/// The current step is held by id, so a step that turns hidden or visible
/// while the wizard runs never shifts the person to another step.
class WizardState<K> {
  final List<WizardStep<K>> steps;

  /// An overview screen before the steps (what is coming, where you were).
  final bool hasOverview;

  /// A summary screen after the last step (every answer, Edit per step).
  final bool hasSummary;

  /// Runs when the wizard finishes: from the summary, or from the last step
  /// without one. Usually a save; [busy] holds while it runs. Returns false
  /// to stay (the app says why). Null: nothing to run.
  final FutureOr<bool> Function()? onComplete;

  /// Fires when a step comes on screen, once for the first one too (funnel
  /// analytics). Keep it cheap.
  final void Function(K id, int index)? onStepChanged;

  final Signal<WizardPhase> phase;
  final Signal<bool> busy = Signal(false, options: SignalOptions(name: 'WizardState.busy'));

  /// When a step's [WizardStep.save] last succeeded in this visit; null
  /// before. The app shows it ("draft saved at 10:21") so the person knows
  /// they can stop and carry on later.
  final Signal<DateTime?> lastSavedAt = Signal(null, options: SignalOptions(name: 'WizardState.lastSavedAt'));

  /// Called with the done and skipped steps whenever either changes, for an
  /// app that keeps them (skips are not in the answers, so without this a
  /// skipped step shows as open again next time). Restore with [skipped].
  final void Function(Set<K> done, Set<K> skipped)? onSettled;

  final DateTime Function() _clock;

  final Signal<K?> _currentId;
  final Signal<Set<K>> _done;
  late final Signal<Set<K>> _skipped;

  /// Set when a step was opened from the summary: leaving it forward goes
  /// back to the summary instead of to the next step.
  final Signal<bool> _fromSummary = Signal(false, options: SignalOptions(name: 'WizardState._fromSummary'));

  /// The steps that take part, in order.
  late final Computed<List<WizardStep<K>>> visibleSteps;

  /// The step on screen (also remembered on the overview and the summary).
  late final Computed<WizardStep<K>?> current;

  /// The current step's position among [visibleSteps]; -1 without one.
  late final Computed<int> index;
  late final Computed<bool> isFirst;
  late final Computed<bool> isLast;

  /// Whether Next may be pressed now: a valid step and no save running.
  late final Computed<bool> canNext;

  /// Whether the current step may be skipped.
  late final Computed<bool> canSkip;

  /// Whether the wizard may finish: every visible required step done, and
  /// no save running.
  late final Computed<bool> canComplete;

  /// Done and skipped steps over all visible ones, 0 to 1.
  late final Computed<double> progress;

  late final EffectCleanup _stepChangedEffect;

  //* A save or completion often closes the wizard's screen, which disposes
  //* this state while the call still runs: nothing may be written after.
  bool _disposed = false;

  WizardState({
    required this.steps,
    this.hasOverview = false,
    this.hasSummary = false,
    this.onComplete,
    this.onStepChanged,
    this.onSettled,
    K? startAt,
    Set<K> skipped = const {},
    DateTime Function()? clock,
  }) : assert(steps.isNotEmpty, 'A wizard needs at least one step'),
       _clock = clock ?? DateTime.now,
       phase = Signal(WizardPhase.step, options: SignalOptions(name: 'WizardState.phase')),
       _currentId = Signal(null, options: SignalOptions(name: 'WizardState._currentId')),
       _done = Signal(
         {for (final step in steps) if (step.answered?.call() ?? false) step.id},
         options: SignalOptions(name: 'WizardState._done'),
       ) {
    //* A restored skip stays a skip only while the step has no answer.
    _skipped = Signal({for (final id in skipped) if (!_done.value.contains(id)) id}, options: SignalOptions(name: 'WizardState._skipped'));
    visibleSteps = computed(
      () => [for (final step in steps) if (step.visible?.call() ?? true) step],
      options: ComputedOptions(name: 'WizardState.visibleSteps'),
    );
    current = computed(() {
      final visible = visibleSteps.value;
      if (visible.isEmpty) return null;
      final id = _currentId.value;
      for (final step in visible) {
        if (step.id == id) return step;
      }
      //* The current step turned hidden: the next visible one after it in
      //* the full list, else the last visible one.
      final at = steps.indexWhere((step) => step.id == id);
      for (final step in steps.skip(at < 0 ? 0 : at)) {
        if (visible.contains(step)) return step;
      }
      return visible.last;
    }, options: ComputedOptions(name: 'WizardState.current'));
    index = computed(() {
      final step = current.value;
      return step == null ? -1 : visibleSteps.value.indexOf(step);
    }, options: ComputedOptions(name: 'WizardState.index'));
    isFirst = computed(() => index.value <= 0, options: ComputedOptions(name: 'WizardState.isFirst'));
    isLast = computed(
      () => index.value == visibleSteps.value.length - 1,
      options: ComputedOptions(name: 'WizardState.isLast'),
    );
    canNext = computed(() {
      final step = current.value;
      return !busy.value && step != null && step.validNow && !step.checkingNow;
    }, options: ComputedOptions(name: 'WizardState.canNext'));
    canSkip = computed(
      () => !busy.value && (current.value?.optional ?? false),
      options: ComputedOptions(name: 'WizardState.canSkip'),
    );
    canComplete = computed(() {
      if (busy.value) return false;
      return visibleSteps.value.every(_settled);
    }, options: ComputedOptions(name: 'WizardState.canComplete'));
    progress = computed(() {
      final visible = visibleSteps.value;
      if (visible.isEmpty) return 0;
      final settled = visible.where((step) => _done.value.contains(step.id) || _skipped.value.contains(step.id));
      return settled.length / visible.length;
    }, options: ComputedOptions(name: 'WizardState.progress'));

    //* No visible step at all: no current step, and the wizard can only complete.
    final start = startAt ?? firstOpen ?? visibleSteps.value.firstOrNull?.id;
    _currentId.value = start;
    if (startAt == null && hasOverview) phase.value = WizardPhase.overview;

    //* Fires once now (the first step on screen) and on every later step.
    (K, int)? last;
    _stepChangedEffect = effect(() {
      final step = current.value;
      final at = index.value;
      if (phase.value != WizardPhase.step || step == null) return;
      final now = (step.id, at);
      if (now == last) return;
      last = now;
      untracked(() => onStepChanged?.call(step.id, at));
    });
  }

  /// Whether [step] lets the wizard finish, checked live: a required step
  /// is valid now and was left forward (or is the one on screen); an
  /// optional step is skipped, or valid when answered. A running check
  /// never counts as settled.
  bool _settled(WizardStep<K> step) {
    if (step.checkingNow) return false;
    final left = _done.value.contains(step.id) || current.value == step;
    if (!step.optional) return left && step.validNow;
    return _skipped.value.contains(step.id) || !left || step.validNow;
  }

  /// The first visible required step that is not valid now: where to send
  /// the person when completion is refused. Null when there is none.
  K? get firstInvalid {
    for (final step in visibleSteps.value) {
      if (!step.optional && (!step.validNow || step.checkingNow)) return step.id;
    }
    return null;
  }

  /// Whether [id] may be opened by a jump (a section tab): every required
  /// step before it is valid now, as with Next one at a time.
  bool reachable(K id) {
    for (final step in visibleSteps.value) {
      if (step.id == id) return true;
      if (!step.optional && (!step.validNow || step.checkingNow)) return false;
    }
    return false;
  }

  /// The first visible step that is neither done nor skipped: where a
  /// returning person carries on. Null when everything is settled.
  K? get firstOpen {
    for (final step in visibleSteps.value) {
      if (!_done.value.contains(step.id) && !_skipped.value.contains(step.id)) return step.id;
    }
    return null;
  }

  /// [id]'s status. Reads signals: call it in a builder to stay current.
  WizardStepStatus statusOf(K id) {
    if (phase.value == WizardPhase.step && current.value?.id == id) return WizardStepStatus.current;
    if (_done.value.contains(id)) return WizardStepStatus.done;
    if (_skipped.value.contains(id)) return WizardStepStatus.skipped;
    return WizardStepStatus.open;
  }

  /// From the overview: on to the first open step (or the first step when
  /// all are settled).
  void begin() {
    batch(() {
      _fromSummary.value = false;
      _currentId.value = firstOpen ?? visibleSteps.value.firstOrNull?.id;
      phase.value = WizardPhase.step;
    });
  }

  /// Opens [id] (from the overview, the summary or a section tab). Opened
  /// from the summary, leaving it forward returns to the summary.
  void goTo(K id) {
    if (busy.value || !reachable(id)) return;
    batch(() {
      _fromSummary.value = phase.value == WizardPhase.summary || _fromSummary.value;
      _currentId.value = id;
      phase.value = WizardPhase.step;
    });
  }

  /// Next: saves the step (when it has [WizardStep.save]), marks it done
  /// and moves on, to the summary, or finishes.
  Future<WizardMove> next() async {
    final step = current.value;
    if (phase.value != WizardPhase.step || step == null || !canNext.value) return WizardMove.stayed;
    final save = step.save;
    if (save != null) {
      busy.value = true;
      final bool ok;
      try {
        ok = await save();
      } finally {
        if (!_disposed) busy.value = false;
      }
      if (!ok || _disposed) return WizardMove.stayed;
      lastSavedAt.value = _clock();
    }
    batch(() {
      _done.value = {..._done.value, step.id};
      _skipped.value = {..._skipped.value}..remove(step.id);
    });
    _report();
    return _advance();
  }

  /// Skips an optional step: no save, no answer, on to the next.
  Future<WizardMove> skip() async {
    final step = current.value;
    if (phase.value != WizardPhase.step || step == null || !canSkip.value) return WizardMove.stayed;
    batch(() {
      _skipped.value = {..._skipped.value, step.id};
      _done.value = {..._done.value}..remove(step.id);
    });
    _report();
    return _advance();
  }

  void _report() => onSettled?.call({..._done.value}, {..._skipped.value});

  Future<WizardMove> _advance() async {
    if (_fromSummary.value && hasSummary) {
      batch(() {
        _fromSummary.value = false;
        phase.value = WizardPhase.summary;
      });
      return WizardMove.moved;
    }
    if (!isLast.value) {
      _currentId.value = visibleSteps.value[index.value + 1].id;
      return WizardMove.moved;
    }
    if (hasSummary) {
      phase.value = WizardPhase.summary;
      return WizardMove.moved;
    }
    return complete();
  }

  /// Back: the previous step, the overview before the first, or [exit]
  /// when there is nothing before. From the summary: the last step.
  WizardMove back() {
    if (busy.value) return WizardMove.stayed;
    switch (phase.value) {
      case WizardPhase.overview:
        return WizardMove.exit;
      case WizardPhase.summary:
        batch(() {
          _currentId.value = visibleSteps.value.lastOrNull?.id;
          phase.value = WizardPhase.step;
        });
        return WizardMove.moved;
      case WizardPhase.step:
        if (_fromSummary.value && hasSummary) {
          batch(() {
            _fromSummary.value = false;
            phase.value = WizardPhase.summary;
          });
          return WizardMove.moved;
        }
        if (!isFirst.value) {
          _currentId.value = visibleSteps.value[index.value - 1].id;
          return WizardMove.moved;
        }
        if (hasOverview) {
          phase.value = WizardPhase.overview;
          return WizardMove.moved;
        }
        return WizardMove.exit;
    }
  }

  /// Finishes: runs [onComplete] with [busy] held. Stays when it returns
  /// false or a required step is still open.
  Future<WizardMove> complete() async {
    if (busy.value || !canComplete.value) return WizardMove.stayed;
    final run = onComplete;
    if (run == null) return WizardMove.completed;
    busy.value = true;
    try {
      return await run() ? WizardMove.completed : WizardMove.stayed;
    } finally {
      if (!_disposed) busy.value = false;
    }
  }

  void dispose() {
    _disposed = true;
    _stepChangedEffect();
    progress.dispose();
    canComplete.dispose();
    canSkip.dispose();
    canNext.dispose();
    isLast.dispose();
    isFirst.dispose();
    index.dispose();
    current.dispose();
    visibleSteps.dispose();
    lastSavedAt.dispose();
    _fromSummary.dispose();
    _skipped.dispose();
    _done.dispose();
    _currentId.dispose();
    busy.dispose();
    phase.dispose();
  }
}
