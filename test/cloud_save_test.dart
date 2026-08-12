// Cloud save is the one subsystem whose bugs are unrecoverable: a merge that
// drops a level takes away something the player earned, and there is no undo.
// The platform calls cannot be reached from a unit test, so what is pinned here
// is the format and the merge — which is where that damage would come from.

import 'package:flutter_test/flutter_test.dart';

import 'package:dotto/progress/progress_store.dart';
import 'package:dotto/services/cloud_save_service.dart';

void main() {
  setUp(() {
    CloudSaveService.resetForTest();
    ProgressStore.clear();
  });

  group('the save format', () {
    test('round-trips', () {
      final json = CloudSaveService.encode(levels: {1, 2, 5}, hintsUsed: 3);
      final back = CloudSaveService.decode(json);
      expect(back, isNotNull);
      expect(back!.levels, {1, 2, 5});
      expect(back.hintsUsed, 3);
    });

    test('carries a schema version', () {
      expect(CloudSaveService.encode(levels: {1}, hintsUsed: 0),
          contains('"version":1'));
    });

    test('writes levels sorted, so two devices produce the same bytes', () {
      expect(CloudSaveService.encode(levels: {5, 1, 3}, hintsUsed: 0),
          contains('[1,3,5]'));
    });

    group('refuses to guess', () {
      test('at nothing', () {
        expect(CloudSaveService.decode(null), isNull);
        expect(CloudSaveService.decode(''), isNull);
      });

      test('at rubbish', () {
        expect(CloudSaveService.decode('not json'), isNull);
        expect(CloudSaveService.decode('{"completedLevels":"nope"}'), isNull);
      });

      test('at a save from a future version', () {
        // A newer game may mean something different by these fields. Ignoring
        // it keeps an old build from overwriting a new save with a bad read.
        final future = '{"completedLevels":[1,2],"hintsUsedTotal":0,'
            '"version":99}';
        expect(CloudSaveService.decode(future), isNull);
      });

      test('but tolerates a missing hint count', () {
        final partial = '{"completedLevels":[1,2],"version":1}';
        final back = CloudSaveService.decode(partial);
        expect(back, isNotNull);
        expect(back!.levels, {1, 2});
        expect(back.hintsUsed, 0);
      });
    });
  });

  group('the merge only ever adds', () {
    test('a cloud save cannot take away a local level', () {
      ProgressStore.markCompleted(1);
      ProgressStore.markCompleted(2);
      ProgressStore.markCompleted(3);
      // Cloud is behind — a second device that has played less.
      ProgressStore.importProgress(levels: {1}, hintsUsed: 0);
      expect(ProgressStore.completed(), containsAll([1, 2, 3]),
          reason: 'a stale cloud save must never erase finished levels');
    });

    test('a local save cannot take away a cloud level', () {
      ProgressStore.markCompleted(1);
      ProgressStore.importProgress(levels: {7, 8}, hintsUsed: 0);
      expect(ProgressStore.completed(), containsAll([1, 7, 8]),
          reason: 'progress from another device must survive the merge');
    });

    test('two divergent devices end up with both halves', () {
      // The case the union exists for: one device played 1–3, the other 4–5.
      ProgressStore.markCompleted(1);
      ProgressStore.markCompleted(2);
      ProgressStore.markCompleted(3);
      ProgressStore.importProgress(levels: {4, 5}, hintsUsed: 0);
      expect(ProgressStore.completed(), containsAll([1, 2, 3, 4, 5]));
    });

    test('the hint count takes the higher of the two', () {
      ProgressStore.bumpHintsUsed();
      ProgressStore.bumpHintsUsed();
      final local = ProgressStore.hintsUsed();

      ProgressStore.importProgress(levels: const {}, hintsUsed: local + 5);
      expect(ProgressStore.hintsUsed(), local + 5);

      // And a lower cloud value does not walk it back.
      ProgressStore.importProgress(levels: const {}, hintsUsed: 0);
      expect(ProgressStore.hintsUsed(), local + 5);
    });

    test('merging nothing changes nothing', () {
      ProgressStore.markCompleted(4);
      final before = ProgressStore.completed();
      ProgressStore.importProgress(levels: const {}, hintsUsed: 0);
      expect(ProgressStore.completed(), before);
    });
  });

  test('saving without a signed-in account does nothing, quietly', () {
    // Sits on the win path. Not signed in is the normal case, not an error.
    expect(() => CloudSaveService.save(), returnsNormally);
  });

  test('loading without a signed-in account completes', () async {
    await expectLater(CloudSaveService.load(), completes);
  });
}
