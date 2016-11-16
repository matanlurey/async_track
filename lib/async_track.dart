import 'dart:async';

import 'package:stack_trace/stack_trace.dart';

/// Returns a [Future] that completes when [action] finishes all work.
///
/// The future completes with whatever value [action] returns.
///
/// If [onError] is set then asynchronous errors are caught and forwarded.
///
/// __Example use__:
///     var stopwatch = new Stopwatch()..start();
///     await runTracked((_) => _computeAsync());
///     print(stopwatch.elapsed);
///
/// You can specifically run some actions _outside_ of the tracking function:
///     var stopwatch = new Stopwatch()..start();
///     await runTracked((tracker) {
///       _computeAsync();
///       tracker.exclude(() => _doSomeReportingWork());
///     });
///
/// Specify a [timerThreshold] to consider scheduled [Timer]s async events:
///     await runTracked((tracker), {
///       _computeAsync();
///     }, timerThreshold: const Duration(milliseconds: 50));
///
/// Track is considered a _simple_ use case for one-off tracking. For more
/// complicated (continuous) tracking, see [AsyncTracker], which is meant to
/// track asynchronous work across long periods of time/multiple actions.
Future/*<E>*/ runTracked/*<E>*/(
  /*=E*/ action(TrackContext context), {
  void onError(AsyncError error),
  Duration timerThreshold: const _Infinity(),
}) async {
  final tracker = new AsyncTracker(timerThreshold: timerThreshold);
  StreamSubscription onErrorSub;
  if (onError != null) {
    onErrorSub = tracker.onError.listen(onError);
  }
  final context = new _AsTrackContext(tracker);
  dynamic/*=E*/ result;
  scheduleMicrotask(() {
    if (onError != null) {
      result = tracker.runGuarded/*<E>*/(() => action(context));
    } else {
      result = tracker.runTracked/*<E>*/(() => action(context));
    }
  });
  await tracker.onTurnEnd.first;
  onErrorSub?.cancel();
  return result;
}

class _Infinity extends Duration {
  const _Infinity();

  @override
  String toString() => 'Infinity';
}

/// Allows entering and exiting tracking during a top-level [runTracked] call.
abstract class TrackContext {
  /// Includes [action] as work before track's future completes.
  ///
  /// __Example use__:
  ///     runTracked((tracker) {
  ///       tracker.exclude(() {
  ///         doBackgroundWork();
  ///         tracker.include(() {
  ///           doWorkDependentOnBackgroundWork();
  ///         });
  ///       });
  ///     });
  ///
  /// This method is a no-op if [isTracking] is `true`.
  ///
  /// It is not typical to need this method, as the root action is already
  /// included, and is provided for edge cases where some non-tracked action is
  /// needed before running a tracked one.
  /*<R>*/ include/*<R>*/(/*=R*/ action());

  /// Excludes [action] as work before track's future completes.
  ///
  /// You may have small background tasks that will in turn spawn additional
  /// work that you _don't_ want to consider as part of the tracked action.
  ///
  /// __Example use__:
  ///     runTracked((tracker) {
  ///       doTrackedComputation();
  ///       tracker.exclude(() {
  ///         doBackgroundWork();
  ///       });
  ///     });
  ///
  /// This method is a no-op if [isTracking] is `false`.
  /*<R>*/ exclude/*<R>*/(/*=R*/ action());

  /// Whether actions are _currently_ being executed within the context.
  ///
  /// __Example use__:
  ///     runTracked((tracker) {
  ///       assert(tracker.isTracking);
  ///       tracker.exclude(() {
  ///         assert(!tracker.isTracking);
  ///       });
  ///     });
  bool get isTracking;
}

/// An exception that is thrown and caught in an asynchronous context.
class AsyncError {
  /// Original exception or error.
  final Object error;

  /// Stack trace where throw occurred.
  final StackTrace stack;

  const AsyncError._(this.error, this.stack);
}

/// Enables tracking an action and all subsequent actions.
abstract class AsyncTracker {
  /// Create a new [AsyncTracker], which forks [Zone.current].
  ///
  /// Specify a [timerThreshold] to consider scheduled [Timer]s async events.
  ///
  /// If [useLongStackTraces] is `true` then generates a long asynchronous
  /// stack trace [onError] - this makes exceptions easier to trace but has a
  /// runtime cost of consistently throwing exceptions to catch stack location.
  factory AsyncTracker({
    Duration timerThreshold: const _Infinity(),
    bool useLongStackTraces: false,
  }) =>
      _ZoneAsyncTracker.fork(Zone.current, timerThreshold, useLongStackTraces);

  /// Whether [onTurnBegin] has emitted but not yet [onTurnEnd].
  bool get inTurn;

  /// Whether actions are _currently_ being executed within the tracker.
  ///
  /// __Example use__:
  ///     asyncTracker.runTracked(() {
  ///       assert(asyncTracker.isTracking);
  ///       asyncTracker.runExcluded(() {
  ///         assert(!asyncTracker.isTracking);
  ///       });
  ///     });
  bool get isTracking;

  /// Fires an event synchronously when a VM turn starts.
  ///
  /// A `VM turn` is considered to have started when the first function body
  /// has executed within the underlying tracking [Zone], and before any
  /// microtasks have executed.
  Stream<Null> get onTurnBegin;

  /// Fires an event synchronously when a VM turn ends.
  ///
  /// A `VM turn` is considered to have ended when the last function body has
  /// executed within the underlying tracking [Zone], and all microtasks started
  /// within the zone have completed.
  Stream<Null> get onTurnEnd;

  /// Fires an event synchronously when the event loop is ended.
  ///
  /// This is considered to happen when [onTurnEnd]'s conditions complete _and_
  /// there are no outstanding (non-periodic) [Timer]s scheduled to still
  /// complete past a threshold time.
  Stream<Null> get onAsyncDone;

  /// Fires an event synchronously when an error occurs.
  Stream<AsyncError> get onError;

  /// Runs [action] _within_ a [Zone] that is tracked.
  ///
  /// Events like [onTurnBegin] and [onTurnEnd] will only occur on actions
  /// started as a result of running [action], and any subsequent asynchronous
  /// work that occurs.
  /*=R*/ runTracked/*<R>*/(/*=R*/ action());

  /// Runs action _within_ a [Zone] that is tracked (like [runTracked]).
  ///
  /// Exceptions that are thrown are forwarded to [onError].
  /*=R*/ runGuarded/*<R>*/(/*=R*/ action());

  /// Runs [action] _outside_ a [Zone] that is tracked.
  ///
  /// Actions that occur as a result of running [action] do not trigger events.
  /*=R*/ runExcluded/*<R>*/(/*=R*/ action());
}

class _AsTrackContext implements TrackContext {
  final AsyncTracker _asyncTracker;

  _AsTrackContext(this._asyncTracker);

  @override
  /*=R*/ exclude/*<R>*/(/*=R*/ action()) => _asyncTracker.runExcluded(action);

  @override
  /*=R*/ include/*<R>*/(/*=R*/ action()) => _asyncTracker.runTracked(action);

  @override
  bool get isTracking => _asyncTracker.isTracking;
}

class _ZoneAsyncTracker implements AsyncTracker {
  final Zone _zone;

  bool _inTurn = false;
  StreamController<Null> _onAsyncDone;
  StreamController<Null> _onTurnBegin;
  StreamController<Null> _onTurnEnd;
  StreamController<AsyncError> _onError;

  int _nestedCalls = 0;
  int _pendingMicrotasks = 0;
  int _pendingTimers = 0;

  _ZoneAsyncTracker._afterInit(this._zone);

  void _check() {
    if (!_inTurn) {
      if (_nestedCalls > 0) {
        _onTurnBegin?.add(null);
        _inTurn = true;
      }
    } else if (_nestedCalls == 0 && _pendingMicrotasks == 0) {
      _onTurnEnd?.add(null);
      _inTurn = false;
      if (_pendingTimers == 0) {
        _onAsyncDone?.add(null);
      }
    }
  }

  static StreamController/*<T>*/ _controller/*<T>*/() {
    return new StreamController/*<T>*/ .broadcast(sync: true);
  }

  static _ZoneAsyncTracker fork(
    Zone zone,
    Duration timerThreshold,
    bool useLongStackTraces,
  ) {
    _ZoneAsyncTracker tracker;
    if (useLongStackTraces) {
      Chain.capture(() {
        tracker = forkInternal(zone, timerThreshold, false);
      }, onError: (error, Chain chain) {
        tracker._zoneError(error, chain);
      });
    } else {
      tracker = forkInternal(zone, timerThreshold, true);
    }
    return tracker;
  }

  static _ZoneAsyncTracker forkInternal(
    Zone zone,
    Duration timerThreshold,
    bool handleUncaughtExceptions,
  ) {
    _ZoneAsyncTracker tracker;
    HandleUncaughtErrorHandler handleUncaughtError;
    if (handleUncaughtExceptions) {
      handleUncaughtError = (self, delegate, zone, error, stack) {
        tracker._zoneError(error, stack);
      };
    }
    return tracker = new _ZoneAsyncTracker._afterInit(
      zone.fork(
        specification: new ZoneSpecification(
          handleUncaughtError: handleUncaughtError,
          run: (self, delegate, zone, fn) {
            return tracker._zoneRun(self, delegate, zone, fn);
          },
          runUnary: (self, delegate, zone, fn, arg) {
            return tracker._zoneRun(self, delegate, zone, () => fn(arg));
          },
          runBinary: (self, delegate, zone, fn, a, b) {
            return tracker._zoneRun(self, delegate, zone, () => fn(a, b));
          },
          scheduleMicrotask: (self, delegate, zone, fn) {
            return tracker._zoneScheduleMicrotask(self, delegate, zone, fn);
          },
          createTimer: (self, delegate, zone, duration, fn) {
            if (timerThreshold is _Infinity || timerThreshold < duration) {
              return delegate.createTimer(zone, duration, fn);
            }
            _WrappedTimer timer;
            tracker._zoneCreateTimer();
            return timer = new _WrappedTimer(
              delegate.createTimer(zone, duration, () {
                try {
                  fn();
                } finally {
                  timer.complete();
                }
              }),
              tracker._zoneCompleteTimer,
            );
          },
        ),
        zoneValues: {zone: true},
      ),
    );
  }

  @override
  bool get inTurn => _inTurn;

  @override
  bool get isTracking => Zone.current == _zone || Zone.current[_zone] == true;

  @override
  Stream<Null> get onAsyncDone =>
      (_onAsyncDone ??= _controller/*<Null>*/()).stream;

  @override
  Stream<Null> get onTurnBegin =>
      (_onTurnBegin ??= _controller/*<Null>*/()).stream;

  @override
  Stream<Null> get onTurnEnd => (_onTurnEnd ??= _controller/*<Null>*/()).stream;

  @override
  Stream<AsyncError> get onError =>
      (_onError ??= _controller/*<AsyncError>*/()).stream;

  @override
  /*=R*/ runExcluded/*<R>*/(/*=R*/ action()) => _zone.parent.run(action);

  @override
  /*=R*/ runGuarded/*<R>*/(/*=R*/ action()) => _zone.runGuarded(action);

  @override
  /*=R*/ runTracked/*<R>*/(/*=R*/ action()) => _zone.run(action);

  void _zoneCreateTimer() {
    _pendingTimers++;
  }

  void _zoneCompleteTimer() {
    _pendingTimers--;
    _check();
  }

  void _zoneError(error, StackTrace stack) {
    if (_onError != null) {
      _onError.add(new AsyncError._(error, stack));
    }
  }

  /*=R*/ _zoneRun/*<R>*/(_, ZoneDelegate parent, Zone zone, /*=R*/ fn()) {
    _nestedCalls++;
    _check();
    try {
      return parent.run(zone, fn);
    } finally {
      _nestedCalls--;
      _check();
    }
  }

  void _zoneScheduleMicrotask(_, ZoneDelegate parent, Zone zone, void fn()) {
    _pendingMicrotasks++;
    _check();
    parent.scheduleMicrotask(zone, () {
      try {
        fn();
      } finally {
        _pendingMicrotasks--;
        _check();
      }
    });
  }
}

typedef void _OnComplete();

class _WrappedTimer implements Timer {
  final _OnComplete _complete;
  final Timer _delegate;

  bool _completed = false;

  _WrappedTimer(this._delegate, this._complete);

  @override
  void cancel() {
    complete();
    _delegate.cancel();
  }

  void complete() {
    if (!_completed) {
      _completed = true;
      _complete();
    }
  }

  @override
  bool get isActive => _delegate.isActive;
}
