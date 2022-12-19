import 'dart:convert';

import 'package:at_client/at_client.dart';
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart';

/// The class responsible to compact the commit log at a frequent time interval.
///
/// The call to [scheduleCompaction] will initiate the commit log compaction. The method
/// accepts an integer which represents the time interval in minutes.
///
/// The call to [getCompactionStats] will returns the metric of the previously run compaction
/// job.
class AtClientCommitLogCompaction {
  static final AtClientCommitLogCompaction _singleton =
      AtClientCommitLogCompaction._internal();

  AtClientCommitLogCompaction._internal();

  factory AtClientCommitLogCompaction.getInstance() {
    return _singleton;
  }

  late AtCommitLog atCommitLog;

  late AtCompactionJob atCompactionJob;

  late SecondaryKeyStore secondaryKeyStore;

  AtCompactionConfig atCompactionConfig = AtCompactionConfig();

  final AtCompactionStats _atCompactionStats = AtCompactionStats();

  /// The call to [scheduleCompaction] will initiate the commit log compaction. The method
  /// accepts an integer which represents the time interval in minutes.
  void scheduleCompaction(int timeIntervalInMins) {
    var atClientCommitLogCompaction = atCompactionConfig
      ..compactionFrequencyInMins = timeIntervalInMins;
    atCompactionJob.scheduleCompactionJob(atClientCommitLogCompaction);
  }

  /// The call to [getCompactionStats] will returns the metric of the previously run compaction
  /// job.
  ///
  /// Fetches the commit log compaction metrics and converts it into an [AtCompactionStats] object
  /// and returns the object.
  ///
  /// When the key is not available, returns [DefaultCompactionStats.getDefaultCompactionStats]
  Future<AtCompactionStats> getCompactionStats() async {
    if (!secondaryKeyStore.isKeyExists(commitLogCompactionKey)) {
      return _atCompactionStats.getDefaultCompactionStats();
    }
    AtData atData = await secondaryKeyStore.get(commitLogCompactionKey);
    var decodedCommitLogCompactionStatsJson = jsonDecode(atData.data!);
    var atCompactionStats = _atCompactionStats
      ..atCompactionType = decodedCommitLogCompactionStatsJson[
          AtCompactionConstants.atCompactionType]
      ..preCompactionEntriesCount = int.parse(
          decodedCommitLogCompactionStatsJson[
              AtCompactionConstants.preCompactionEntriesCount])
      ..postCompactionEntriesCount = int.parse(
          decodedCommitLogCompactionStatsJson[
              AtCompactionConstants.postCompactionEntriesCount])
      ..lastCompactionRun = DateTime.parse(decodedCommitLogCompactionStatsJson[
          AtCompactionConstants.lastCompactionRun])
      ..deletedKeysCount = int.parse(decodedCommitLogCompactionStatsJson[
          AtCompactionConstants.deletedKeysCount])
      ..compactionDurationInMills = int.parse(
          decodedCommitLogCompactionStatsJson[
              AtCompactionConstants.compactionDurationInMills]);
    return atCompactionStats;
  }
}

/// An extension class on AtCompactionStats for the default compaction stats on client commit log
/// when the [commitLogCompactionKey] is not available
extension DefaultCompactionStats on AtCompactionStats {
  getDefaultCompactionStats() {
    return AtCompactionStats()
      ..atCompactionType = 'AtCommitLog'
      ..compactionDurationInMills = -1
      ..preCompactionEntriesCount = -1
      ..postCompactionEntriesCount = -1
      ..deletedKeysCount = -1
      ..lastCompactionRun = DateTime.fromMillisecondsSinceEpoch(0);
  }
}
