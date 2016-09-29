import 'dart:async';

import 'package:async_track/async_track.dart';
import 'package:async_track/src/cache.dart';
import 'package:test/test.dart';

void main() {
  // Disable caching of trackers to be able to get hermetic tests.
  enableTrackerCaching = false;

  List<String> logs;

  setUp(() => logs = <String>[]);

  group('$runTracked', () {
    test('should complete for a single method', () async {
      logs.add('Start');
      await runTracked((_) => logs.add('Execute'));
      logs.add('End');
      expect(logs, ['Start', 'Execute', 'End']);
    });

    test('should complete for multiple methods', () async {
      logs.add('Start');
      await runTracked((context) {
        context.include(() {
          context.include(() {
            logs.add('Execute');
          });
        });
      });
      logs.add('End');
      expect(logs, ['Start', 'Execute', 'End']);
    });

    test('should complete for microtasks', () async {
      logs.add('Start');
      await runTracked((_) {
        scheduleMicrotask(() {
          scheduleMicrotask(() {
            scheduleMicrotask(() {
              logs.add('Execute');
            });
          });
        });
      });
      logs.add('End');
      expect(logs, ['Start', 'Execute', 'End']);
    });

    test('should support excluding microtasks', () async {
      logs.add('Start');
      await runTracked((context) {
        scheduleMicrotask(() {
          context.exclude(() {
            scheduleMicrotask(() {
              scheduleMicrotask(() {
                logs.add('Excluded');
              });
            });
          });
          scheduleMicrotask(() {
            logs.add('Included');
          });
        });
      });
      logs.add('End');
      await new Future.delayed(Duration.ZERO);
      expect(logs, ['Start', 'Included', 'End', 'Excluded']);
    });
  });

  group('$AsyncTracker', () {
    test('should determine the start and end of microtask loops', () async {
      logs.add('Start');
      var tracker = new AsyncTracker();
      tracker.onTurnBegin.listen((_) => logs.add('--- vm turn begin ---'));
      tracker.onTurnEnd.listen((_) => logs.add('--- vm turn end ---'));
      tracker.runTracked(() {
        scheduleMicrotask(() {
          logs.add('scheduleMicrotask#1');
          Timer.run(() {
            logs.add('--- event loop ---');
            scheduleMicrotask(() {
              logs.add('scheduleMicrotask#2');
            });
          });
        });
      });
      await new Future.delayed(const Duration(milliseconds: 1));
      expect(logs, [
        'Start',
        '--- vm turn begin ---',
        'scheduleMicrotask#1',
        '--- vm turn end ---',
        '--- vm turn begin ---',
        '--- event loop ---',
        'scheduleMicrotask#2',
        '--- vm turn end ---',
      ]);
    });
  });
}
