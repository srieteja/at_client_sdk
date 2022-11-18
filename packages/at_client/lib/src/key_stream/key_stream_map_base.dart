import 'dart:async';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/key_stream/key_stream_mixin.dart';
import 'package:meta/meta.dart';

class KeyStreamMapBase<K, V, I extends Map<K, V>> extends KeyStreamMixin<I> implements Stream<I> {
  @visibleForTesting
  final Map<String, MapEntry<K, V>> store = {};

  /// {@macro KeyStreamCastTo}
  final I Function(Iterable<MapEntry<K, V>> values) _castTo;

  /// {@macro KeyStreamGenerateRef}
  final String Function(AtKey key, AtValue value) _generateRef;

  @override
  void handleStreamEvent(AtKey key, AtValue value, KeyStreamOperation operation) {
    switch (operation) {
      case KeyStreamOperation.none:
      // TODO this is the resulting value from CommitOp being null, i.e. keyInfo.operation == null
      // Should I assume that the Key is bad and should be removed from the stream, OR
      // Should I do nothing to the Key... can CommitOp even be null here?
      case KeyStreamOperation.delete:
        store.remove(_generateRef(key, value));
        break;
      default:
        store[_generateRef(key, value)] = convert(key, value)! as MapEntry<K, V>;
    }
    controller.add(_castTo(store.values));
  }

  KeyStreamMapBase({
    required MapEntry<K, V>? Function(AtKey, AtValue) convert,
    String? regex,
    bool shouldGetKeys = true,
    String? sharedBy,
    String? sharedWith,
    String Function(AtKey key, AtValue value)? generateRef,
    I Function(Iterable<MapEntry<K, V>> values)? castTo,
    FutureOr<void> Function(Object exception, [StackTrace? stackTrace])? onError,
    AtClientManager? atClientManager,
  })  : _generateRef = generateRef ?? ((key, value) => key.key ?? ''),
        _castTo = castTo ?? ((Iterable<MapEntry<K, V>> values) => values as I),
        super(
          convert: convert,
          regex: regex,
          sharedBy: sharedBy,
          sharedWith: sharedWith,
          shouldGetKeys: shouldGetKeys,
          onError: onError,
          atClientManager: atClientManager,
        );
}
