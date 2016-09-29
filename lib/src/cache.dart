import 'package:meta/meta.dart';

/// If `false`, creating multiple `AsyncTracker` per `Zone`.
///
/// In tests, this should be manually set to avoid caching.
@visibleForTesting
bool enableTrackerCaching = true;
