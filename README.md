# async_track

[![Build Status](https://travis-ci.org/matanlurey/async_track.svg?branch=master)](https://travis-ci.org/matanlurey/async_track)

Provides a mechanism for tracking asynchronous events in Dart.

This package is **experimental** and subject to change. It currently
only has knowledge of _microtasks_ and _timers_, and ignores other forms
of asynchronous events DOM access, network events, file I/O.

## Usage

You can use track asynchronous events _once_ or _continuously_.

### runTracked

`Future/*<E>*/ runTracked/*<E>*/(/*=E*/ action())` runs `action` within
a [Zone][zones], and returns a [Future][futures] when all asynchronous
events started by `action` (or started by other events) complete.

For example, waiting for some tasks to complete:

```dart
await runTracked(() {
  // Any of these could use 'scheduleMicrotask' to schedule work.
  doTask1();
  doTask2();
  doTask3();
});
```

### AsyncTracker

For continuous tracking, you can use `AsyncTracker`, which reports
progress of asynchronous events continuously. See `async_track.dart`.

## How it works

Uses the Dart [Zone][zones] API to create an _execution context_ where
a function call and all of it's associated calls and asynchronous tasks
are associated with that zone.

[futures]: https://www.dartlang.org/tutorials/language/futures
[zones]: https://www.dartlang.org/articles/libraries/zones
