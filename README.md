# step_kit

A wizard state machine for Flutter apps built on signals, kept in one place
so every app that draws a step-by-step flow gets the same behaviour. The kit
holds the behaviour; each app draws it in its own look.

- `WizardStep<K>` (`lib/src/wizard_step.dart`): one step, keyed by an id. `isValid` and `checking` are read live (a required step that turns invalid later blocks completion again; a running check holds Next), `visible` leaves a step out, `optional` allows Skip, `save` stores the answer on Next (false stays), `answered` starts it as done.
- `WizardState<K>` (`wizard_state.dart`): the step on screen (held by id, so a step turning hidden never shifts the person), done and skipped steps, `busy` while a save or the completion runs, an optional overview before the steps (resume at the first open step) and summary after them (an edit returns to it), jumps limited to `reachable` steps, `progress`, `firstOpen`, `firstInvalid`, `lastSavedAt` (show "draft saved" so the person knows they can carry on later), `onSettled` + `skipped` (keep and restore skipped steps, which are not in the answers), and `onStepChanged` for funnel analytics.
- Moves: `begin`, `next`, `skip`, `back`, `goTo`, `complete`. Each returns a `WizardMove` (`moved`, `stayed`, `exit`, `completed`) for the app to react to.

## Use

```yaml
dependencies:
  step_kit:
    git:
      url: https://github.com/<owner>/step_kit.git
      ref: v0.2.0
```

```dart
final wizard = WizardState<MyStep>(
  steps: [
    WizardStep(id: MyStep.name, isValid: () => name.value.isNotEmpty),
    WizardStep(id: MyStep.photo, optional: true, visible: () => wantsPhoto.value),
  ],
  hasSummary: true,
  onComplete: () async => save(),
);
```

A fix here reaches an app when that app raises `ref`.

## Check

```bash
flutter pub get
flutter analyze
flutter test
```
