import 'package:flutter_test/flutter_test.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:step_kit/step_kit.dart';

enum S { a, b, c, d }

void main() {
  group('moving', () {
    test('next walks the steps and finishes on the last without a summary', () async {
      var completed = 0;
      final w = WizardState<S>(
        steps: [for (final s in [S.a, S.b, S.c]) WizardStep(id: s)],
        onComplete: () => ++completed > 0,
      );
      expect(w.phase.value, WizardPhase.step);
      expect(w.current.value!.id, S.a);
      expect(await w.next(), WizardMove.moved);
      expect(await w.next(), WizardMove.moved);
      expect(w.isLast.value, isTrue);
      expect(await w.next(), WizardMove.completed);
      expect(completed, 1);
      expect(w.progress.value, 1);
      w.dispose();
    });

    test('back: previous step, then exit; with an overview, the overview first', () {
      final plain = WizardState<S>(steps: [WizardStep(id: S.a), WizardStep(id: S.b)], startAt: S.b);
      expect(plain.back(), WizardMove.moved);
      expect(plain.current.value!.id, S.a);
      expect(plain.back(), WizardMove.exit);
      plain.dispose();

      final withOverview = WizardState<S>(steps: [WizardStep(id: S.a)], hasOverview: true);
      expect(withOverview.phase.value, WizardPhase.overview);
      withOverview.begin();
      expect(withOverview.phase.value, WizardPhase.step);
      expect(withOverview.back(), WizardMove.moved);
      expect(withOverview.phase.value, WizardPhase.overview);
      expect(withOverview.back(), WizardMove.exit);
      withOverview.dispose();
    });

    test('the summary follows the last step; an edit from it returns to it', () async {
      final w = WizardState<S>(steps: [WizardStep(id: S.a), WizardStep(id: S.b), WizardStep(id: S.c)], hasSummary: true);
      await w.next();
      await w.next();
      await w.next();
      expect(w.phase.value, WizardPhase.summary);
      w.goTo(S.a);
      expect(w.phase.value, WizardPhase.step);
      expect(w.statusOf(S.a), WizardStepStatus.current);
      expect(await w.next(), WizardMove.moved);
      expect(w.phase.value, WizardPhase.summary, reason: 'not on to b');
      w.goTo(S.b);
      expect(w.back(), WizardMove.moved);
      expect(w.phase.value, WizardPhase.summary, reason: 'back from an edit returns too');
      expect(await w.complete(), WizardMove.completed);
      w.dispose();
    });
  });

  group('skip and resume', () {
    test('only an optional step skips; skipped and done are exclusive', () async {
      final w = WizardState<S>(steps: [WizardStep(id: S.a), WizardStep(id: S.b, optional: true), WizardStep(id: S.c)]);
      expect(w.canSkip.value, isFalse);
      expect(await w.skip(), WizardMove.stayed);
      await w.next();
      expect(w.canSkip.value, isTrue);
      expect(await w.skip(), WizardMove.moved);
      expect(w.statusOf(S.b), WizardStepStatus.skipped);
      w.back();
      await w.next();
      w.back();
      expect(w.statusOf(S.b), WizardStepStatus.current);
      await w.next();
      expect(w.statusOf(S.b), WizardStepStatus.done);
      w.dispose();
    });

    test('answered steps start done; the overview resumes at the first open one', () {
      final w = WizardState<S>(
        steps: [WizardStep(id: S.a, answered: () => true), WizardStep(id: S.b), WizardStep(id: S.c)],
        hasOverview: true,
      );
      expect(w.statusOf(S.a), WizardStepStatus.done);
      expect(w.firstOpen, S.b);
      w.begin();
      expect(w.current.value!.id, S.b);
      expect(w.progress.value, closeTo(1 / 3, 1e-9));
      w.dispose();
    });
  });

  group('live checks', () {
    test('a required step blocks Next until valid, and completion when it turns invalid again', () async {
      final name = signal('');
      final w = WizardState<S>(
        steps: [WizardStep(id: S.a, isValid: () => name.value.isNotEmpty), WizardStep(id: S.b)],
        hasSummary: true,
      );
      expect(w.canNext.value, isFalse);
      expect(await w.next(), WizardMove.stayed);
      name.value = 'Team';
      expect(w.canNext.value, isTrue);
      await w.next();
      await w.next();
      expect(w.canComplete.value, isTrue);
      name.value = '';
      expect(w.canComplete.value, isFalse, reason: 'checked live, not only when left');
      expect(await w.complete(), WizardMove.stayed);
      expect(w.firstInvalid, S.a);
      name.value = 'Team';
      expect(await w.complete(), WizardMove.completed);
      w.dispose();
    });

    test('a running check holds Next and completion', () async {
      final checking = signal(true);
      final w = WizardState<S>(steps: [WizardStep(id: S.a, checking: () => checking.value)]);
      expect(w.canNext.value, isFalse);
      expect(w.canComplete.value, isFalse);
      checking.value = false;
      expect(w.canNext.value, isTrue);
      expect(await w.next(), WizardMove.completed);
      w.dispose();
    });

    test('a jump cannot pass an invalid required step', () {
      final ok = signal(false);
      final w = WizardState<S>(steps: [WizardStep(id: S.a, isValid: () => ok.value), WizardStep(id: S.b, optional: true), WizardStep(id: S.c)]);
      expect(w.reachable(S.a), isTrue);
      expect(w.reachable(S.c), isFalse);
      w.goTo(S.c);
      expect(w.current.value!.id, S.a);
      ok.value = true;
      w.goTo(S.c);
      expect(w.current.value!.id, S.c, reason: 'an optional step never blocks a jump');
      w.dispose();
    });

    test('an optional step left without an answer does not block completion', () async {
      final w = WizardState<S>(steps: [WizardStep(id: S.a), WizardStep(id: S.b, optional: true, isValid: () => false)], hasSummary: true);
      await w.next();
      await w.skip();
      expect(w.canComplete.value, isTrue);
      w.dispose();
    });
  });

  group('saving', () {
    test('save per step holds busy, stays on false, moves on true', () async {
      var answer = false;
      final saves = <S>[];
      late WizardState<S> w;
      w = WizardState<S>(
        steps: [
          WizardStep(
            id: S.a,
            save: () async {
              saves.add(S.a);
              expect(w.busy.value, isTrue);
              expect(w.canNext.value, isFalse, reason: 'no double tap while saving');
              return answer;
            },
          ),
          WizardStep(id: S.b),
        ],
      );
      expect(await w.next(), WizardMove.stayed);
      expect(w.current.value!.id, S.a);
      expect(w.busy.value, isFalse);
      answer = true;
      expect(await w.next(), WizardMove.moved);
      expect(saves, [S.a, S.a]);
      w.dispose();
    });

    test('a refused completion stays and releases busy; a throwing save releases it too', () async {
      final w = WizardState<S>(steps: [WizardStep(id: S.a)], onComplete: () async => false);
      expect(await w.next(), WizardMove.stayed);
      expect(w.busy.value, isFalse);
      w.dispose();

      final t = WizardState<S>(steps: [WizardStep(id: S.a, save: () async => throw StateError('offline'))]);
      await expectLater(t.next(), throwsStateError);
      expect(t.busy.value, isFalse);
      t.dispose();
    });

    test('a completion or save that closes the screen writes nothing after dispose', () async {
      late final WizardState<S> w;
      w = WizardState<S>(
        steps: [WizardStep(id: S.a)],
        onComplete: () async {
          w.dispose();
          return true;
        },
      );
      expect(await w.next(), WizardMove.completed);

      late final WizardState<S> saving;
      saving = WizardState<S>(
        steps: [
          WizardStep(
            id: S.a,
            save: () async {
              saving.dispose();
              return true;
            },
          ),
          WizardStep(id: S.b),
        ],
      );
      expect(await saving.next(), WizardMove.stayed);
    });
  });

  group('visibility', () {
    test('a hidden step is skipped and not counted; the current one never shifts', () async {
      final photo = signal(false);
      final w = WizardState<S>(steps: [WizardStep(id: S.a), WizardStep(id: S.b, visible: () => photo.value), WizardStep(id: S.c)]);
      expect(w.visibleSteps.value.map((s) => s.id), [S.a, S.c]);
      await w.next();
      expect(w.current.value!.id, S.c);
      photo.value = true;
      expect(w.current.value!.id, S.c, reason: 'held by id');
      expect(w.index.value, 2);
      w.dispose();
    });

    test('the current step turning hidden moves to the next visible one', () {
      final show = signal(true);
      final w = WizardState<S>(steps: [WizardStep(id: S.a), WizardStep(id: S.b, visible: () => show.value), WizardStep(id: S.c)], startAt: S.b);
      show.value = false;
      expect(w.current.value!.id, S.c);
      w.dispose();
    });
  });

  test('a saved step stamps lastSavedAt; skips are reported and restored', () async {
    final settled = <(Set<S>, Set<S>)>[];
    final w = WizardState<S>(
      steps: [WizardStep(id: S.a, save: () => true), WizardStep(id: S.b, optional: true), WizardStep(id: S.c)],
      clock: () => DateTime(2026, 11, 26, 10, 21),
      onSettled: (done, skipped) => settled.add((done, skipped)),
    );
    expect(w.lastSavedAt.value, isNull);
    await w.next();
    expect(w.lastSavedAt.value, DateTime(2026, 11, 26, 10, 21));
    await w.skip();
    expect(settled.last.$1, {S.a});
    expect(settled.last.$2, {S.b});
    w.dispose();

    final again = WizardState<S>(
      steps: [WizardStep(id: S.a, answered: () => true), WizardStep(id: S.b, optional: true), WizardStep(id: S.c)],
      skipped: {S.b, S.a},
      hasOverview: true,
    );
    expect(again.statusOf(S.b), WizardStepStatus.skipped);
    expect(again.statusOf(S.a), WizardStepStatus.done, reason: 'an answer wins over a stored skip');
    expect(again.firstOpen, S.c);
    again.dispose();
  });

  test('onStepChanged fires for the first step and each later one, not on the overview', () async {
    final seen = <(S, int)>[];
    final w = WizardState<S>(
      steps: [WizardStep(id: S.a), WizardStep(id: S.b)],
      hasOverview: true,
      onStepChanged: (id, index) => seen.add((id, index)),
    );
    expect(seen, isEmpty);
    w.begin();
    await w.next();
    w.back();
    expect(seen, [(S.a, 0), (S.b, 1), (S.a, 0)]);
    w.dispose();
  });
}
