import 'dart:async';

import 'package:async_track/async_track.dart';
import 'package:test/test.dart';

void main() {
  List<String> logs;

  setUp(() => logs = <String>[]);

  group('$runTracked', () {
    test('should complete for a single method', () async {
      logs.add('start');
      await runTracked((_) => logs.add('execute'));
      logs.add('end');
      expect(logs, ['start', 'execute', 'end']);
    });

    test('should complete for multiple methods', () async {
      logs.add('start');
      await runTracked((context) {
        context.include(() {
          context.include(() {
            logs.add('execute');
          });
        });
      });
      logs.add('end');
      expect(logs, ['start', 'execute', 'end']);
    });

    test('should complete for microtasks', () async {
      logs.add('start');
      await runTracked((_) {
        scheduleMicrotask(() {
          scheduleMicrotask(() {
            scheduleMicrotask(() {
              logs.add('execute');
            });
          });
        });
      });
      logs.add('end');
      expect(logs, ['start', 'execute', 'end']);
    });

    test('should support excluding microtasks', () async {
      logs.add('start');
      await runTracked((context) {
        scheduleMicrotask(() {
          context.exclude(() {
            scheduleMicrotask(() {
              scheduleMicrotask(() {
                logs.add('excluded');
              });
            });
          });
          scheduleMicrotask(() {
            logs.add('included');
          });
        });
      });
      logs.add('end');
      await new Future.delayed(Duration.ZERO);
      expect(logs, ['start', 'included', 'end', 'excluded']);
    });

    test('should support catching exceptions', () async {
      logs.add('start');
      await runTracked((context) {
        scheduleMicrotask(() {
          throw new StateError('Intentional');
        });
      }, onError: (error) {
        logs.add('error: ${error.error.runtimeType}');
      });
      logs.add('end');
      await new Future.delayed(Duration.ZERO);
      expect(logs, ['start', 'error: StateError', 'end']);
    });
  });

  group('$AsyncTracker', () {
    test('should determine the start and end of microtask loops', () async {
      logs.add('start');
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
      await new Future.delayed(const Duration(milliseconds: 100));
      expect(logs, [
        'start',
        '--- vm turn begin ---',
        'scheduleMicrotask#1',
        '--- vm turn end ---',
        '--- vm turn begin ---',
        '--- event loop ---',
        'scheduleMicrotask#2',
        '--- vm turn end ---',
      ]);
    });

    test('should track timers as well', () async {
      logs.add('start');
      var tracker = new AsyncTracker(timerThreshold: Duration.ZERO);
      tracker.onTurnBegin.listen((_) => logs.add('--- vm turn begin ---'));
      tracker.onTurnEnd.listen((_) => logs.add('--- vm turn end ---'));
      tracker.onAsyncDone.listen((_) => logs.add('--- async done ---'));
      tracker.runTracked(() {
        scheduleMicrotask(() {
          logs.add('scheduleMicrotask#1');
          Timer.run(() {
            logs.add('timer#1');
            scheduleMicrotask(() {
              logs.add('scheduleMicrotask#2');
            });
          });
        });
      });
      await tracker.onAsyncDone.first;
      expect(logs, [
        'start',
        '--- vm turn begin ---',
        'scheduleMicrotask#1',
        '--- vm turn end ---',
        '--- vm turn begin ---',
        'timer#1',
        'scheduleMicrotask#2',
        '--- vm turn end ---',
        '--- async done ---'
      ]);
    });

    test('should track exceptions as well', () async {
      logs.add('start');
      var tracker = new AsyncTracker(timerThreshold: Duration.ZERO);
      tracker.onTurnBegin.listen((_) => logs.add('--- vm turn begin ---'));
      tracker.onTurnEnd.listen((_) => logs.add('--- vm turn end ---'));
      tracker.onAsyncDone.listen((_) => logs.add('--- async done ---'));
      tracker.onError.listen((_) => logs.add('--- error ---'));
      tracker.runTracked(() {
        scheduleMicrotask(() {
          logs.add('scheduleMicrotask#1');
          Timer.run(() {
            logs.add('timer#1');
            scheduleMicrotask(() {
              throw new StateError('Intentional');
            });
          });
        });
      });
      await tracker.onAsyncDone.first;
      expect(logs, [
        'start',
        '--- vm turn begin ---',
        'scheduleMicrotask#1',
        '--- vm turn end ---',
        '--- vm turn begin ---',
        'timer#1',
        '--- error ---',
        '--- vm turn end ---',
        '--- async done ---'
      ]);
    });
  });
}
