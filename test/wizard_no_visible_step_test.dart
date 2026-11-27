import 'package:flutter_test/flutter_test.dart';
import 'package:step_kit/step_kit.dart';

void main() {
  test('a wizard whose steps are all hidden has no current step and can only complete', () async {
    final w = WizardState<String>(
      steps: [WizardStep(id: 'a', visible: () => false)],
      hasOverview: true,
      hasSummary: true,
    );
    expect(w.current.value, isNull);
    w.begin();
    expect(w.current.value, isNull);
    expect(await w.next(), WizardMove.stayed);
    expect(await w.complete(), WizardMove.completed);
    w.phase.value = WizardPhase.summary;
    expect(w.back(), WizardMove.moved);
    expect(w.current.value, isNull);
    w.dispose();
  });
}
