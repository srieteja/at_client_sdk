import 'dart:convert';

import 'package:at_client/src/presence_service/presence_model.dart';
import 'package:at_client/src/response/json_utils.dart';
import 'package:at_client/src/util/at_client_util.dart';
import 'package:at_client/src/client/at_client_spec.dart';
import 'package:at_commons/at_commons.dart';

class AtPresenceService {
  late AtClient atClient;

  AtPresenceService(this.atClient);

  Future<void> setPresence(Presence presence, {String? atSign}) async {
    if (atSign.isNull) {
      await _setGlobalPresence(presence);
      return;
    }
    // create a shared key for atSign in users namespace and also notify
    await _setPresenceFor(atSign!, presence);
  }

  Future<Presence> getPresence({String? atSign}) async {
    late Map decodedResponse;
    if (atSign.isNotNull) {
      decodedResponse = await _getAtSignSpecificPresence(atSign!);
    }
    if (atSign.isNull) {
      decodedResponse = await _getGlobalPresence();
    }

    List<PresenceServices> presenceServiceList = [];
    return Presence(
        AtClientUtil.getStatusFromName(
            decodedResponse[PresenceServiceConstants.presenceStatus]),
        presenceServiceList.fromJson(jsonDecode(decodedResponse[
        PresenceServiceConstants.presenceServiceListStatus])),
        decodedResponse[PresenceServiceConstants.description]);
  }

  Future<void> _setGlobalPresence(Presence presence) async {
    AtKey atKey = (AtKey.public(PresenceServiceConstants.key,
        namespace: atClient.getCurrentAtSign()?.replaceFirst('@', ''))
      ..sharedBy(atClient.getCurrentAtSign()!))
        .build();
    await atClient.put(atKey, jsonEncode(presence.toJson()));
  }

  Future<void> _setPresenceFor(String atSign, Presence presence) async {
    var atKey = AtKey()
      ..key = PresenceServiceConstants.key
      ..namespace = atClient.getCurrentAtSign()?.replaceFirst('@', '')
      ..sharedWith = atSign
      ..sharedBy = atClient.getCurrentAtSign()!
      ..metadata = (Metadata()
        ..ttr = 86400
        ..ccd = true);

    await atClient.put(atKey, jsonEncode(presence.toJson()));
  }

  Future<Map> _getGlobalPresence() async {
    AtKey atKey = AtKey()
      ..key = PresenceServiceConstants.key
      ..namespace = atClient.getCurrentAtSign()?.replaceFirst('@', '')
      ..metadata = (Metadata()
        ..isPublic = true)
      ..sharedBy = atClient.getCurrentAtSign();
    var presenceResponse = await atClient.get(atKey);
    return JsonUtils.decodeJson(presenceResponse.value);
  }

  Future<Map> _getAtSignSpecificPresence(String atSign) async {
    AtKey atKey = AtKey()
      ..key = PresenceServiceConstants.key
      ..namespace = atClient.getCurrentAtSign()?.replaceFirst('@', '')
      ..sharedWith = atSign
      ..sharedBy = atClient.getCurrentAtSign();
    var presenceResponse = await atClient.get(atKey);
    return JsonUtils.decodeJson(presenceResponse.value);
  }
}
