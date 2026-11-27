# Changelog

All notable changes to this package. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the package uses [semantic versioning](https://semver.org/) (pre-1.0: a minor bump may break the API). Each version is a git tag (`vX.Y.Z`) with a GitHub release.

## [0.2.1] - 2026-11-27
### Fixed
- A wizard whose steps are all hidden no longer throws when it opens, begins or goes back from the summary: it has no current step and can only complete.

## [0.2.0] - 2026-11-26
### Added
- `lastSavedAt`: when a step's save last succeeded, so an app can show "draft saved" and the person knows they can carry on later.
- `onSettled` + `skipped`: report done and skipped steps for the app to keep, and restore skips (an answer wins over a stored skip).
### Fixed
- A save or completion that closes the screen disposes the wizard: `busy` is no longer written after dispose, and `next()` stops when the wizard was disposed during the save.

## [0.1.0] - 2026-11-26
### Added
- `WizardState<K>` / `WizardStep<K>`: a wizard state machine with live checks (`isValid`, `checking`), visibility, optional steps and skip, save per step, resume at the first open step, an overview before and a summary after the steps, and `onStepChanged` for analytics.

[0.2.0]: https://github.com/arnoutvandervorst/step_kit/releases/tag/v0.2.0
[0.1.0]: https://github.com/arnoutvandervorst/step_kit/releases/tag/v0.1.0
