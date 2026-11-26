import 'dart:async';

/// One step of a wizard, keyed by [id] (an enum value, a string).
///
/// [isValid], [visible] and [save] may read signals: the wizard recomputes
/// when they change.
class WizardStep<K> {
  final K id;

  /// Whether the step's answer is valid now. Read live: a required step
  /// that turns invalid after it was left blocks completion again. Null:
  /// always valid.
  final bool Function()? isValid;

  /// Whether a check of the answer is still running (a name that must be
  /// free, a number looked up): Next waits, the app may show a spinner.
  /// Null: never.
  final bool Function()? checking;

  /// Whether the step takes part (a photo step only when the task asks for
  /// one). Null: always. A hidden step is neither shown nor counted.
  final bool Function()? visible;

  /// Whether the person may skip it without filling it in.
  final bool optional;

  /// Stores this step's answer when the person leaves it forward (Next).
  /// Returns false to stay on the step (the app says why). Null: nothing to
  /// store per step; the wizard's own completion stores everything.
  final FutureOr<bool> Function()? save;

  /// Whether this step already holds an answer when the wizard opens (a
  /// draft from earlier today): it starts as done, and resuming skips it.
  final bool Function()? answered;

  const WizardStep({
    required this.id,
    this.isValid,
    this.checking,
    this.visible,
    this.optional = false,
    this.save,
    this.answered,
  });

  bool get validNow => isValid?.call() ?? true;

  bool get checkingNow => checking?.call() ?? false;
}

/// Where a step stands.
enum WizardStepStatus {
  /// Not reached, or reached and left without an answer.
  open,

  /// The step on screen.
  current,

  /// Left forward with a valid (and saved) answer.
  done,

  /// Skipped on purpose.
  skipped,
}

/// What the wizard shows: the overview before the steps, a step, or the
/// summary after the last one.
enum WizardPhase { overview, step, summary }

/// The outcome of a move, for the app to react to.
enum WizardMove {
  /// Moved (to another step, the overview or the summary).
  moved,

  /// Not moved: the step is invalid, a save is running, or the save failed.
  stayed,

  /// Back on the first step without an overview: the app closes the wizard.
  exit,

  /// The wizard finished (its completion ran and succeeded).
  completed,
}
