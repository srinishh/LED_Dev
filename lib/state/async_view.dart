import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/order_repository.dart';

/// How a screen renders an asynchronous read.
///
/// `AsyncValue.when` treats a reload as loading even when the reload has
/// already failed, which leaves the user watching a skeleton that will never
/// resolve. Screens use this instead, so a failure always surfaces as an
/// error with a way forward, and a permission problem is told apart from a
/// transport problem.
extension AsyncView<T> on AsyncValue<T> {
  Widget view({
    required Widget Function(T value) data,
    required Widget Function() loading,
    required Widget Function(String message, bool canRetry) error,
    Widget Function(String message)? denied,
  }) {
    final failure = this.error;
    if (hasError && failure != null) {
      if (failure is PermissionFailure && denied != null) {
        return denied(failure.message);
      }
      final canRetry =
          failure is RepositoryFailure ? failure.canRetry : true;
      return error(_messageFor(failure), canRetry);
    }

    // A reload keeps the previous value on screen rather than flashing back
    // to a skeleton, which would make the list jump under the user.
    if (hasValue) return data(requireValue);

    return loading();
  }

  static String _messageFor(Object failure) => switch (failure) {
        RepositoryFailure(:final message) => message,
        PermissionFailure(:final message) => message,
        _ => 'Something went wrong while loading. Try again in a moment.',
      };
}
