/// The class contains all the client configurations.
class AtClientConfig {
  static final AtClientConfig _singleton = AtClientConfig._internal();

  AtClientConfig._internal();

  factory AtClientConfig.getInstance() {
    return _singleton;
  }

  /// Represents the at_client version.
  final String atClientVersion = '3.0.45';
}
