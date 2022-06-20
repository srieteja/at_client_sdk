import 'dart:convert';

class Presence {
  // Possible values = {available,unavailable}
  late PresenceStatus presenceStatus;

  // List of service
  late List<PresenceServices> presenceServicesList;

  late String description;

  Presence(this.presenceStatus, this.presenceServicesList, this.description);

  Map toJson() => {
        PresenceServiceConstants.presenceStatus: presenceStatus.name,
        PresenceServiceConstants.presenceServiceListStatus:
            jsonEncode(presenceServicesList.toJson()),
        PresenceServiceConstants.description: description
      };

  @override
  String toString() {
    return 'presenceStatus: ${presenceStatus.name}  presenceServicesList: ${presenceServicesList.toString()}  description: $description';
  }
}

enum PresenceServices { call, message }

enum PresenceStatus { available, unavailable }

extension PresenceServiceListJson on List<PresenceServices> {
  Map toJson() {
    Map jsonMap = {};
    for (var element in this) {
      jsonMap.putIfAbsent(element.index.toString(), () => element.name);
    }
    return jsonMap;
  }

  List<PresenceServices> fromJson(Map json) {
    List<PresenceServices> tempList = [];
    json.forEach((key, value) {
      tempList.add(_getServiceFromString(value));
    });
    return tempList;
  }

  PresenceServices _getServiceFromString(String service) {
    if (service == 'call') {
      return PresenceServices.call;
    }
    return PresenceServices.message;
  }
}

abstract class PresenceServiceConstants {
  static String presenceStatus = 'presenceStatus';
  static String presenceServiceListStatus = 'presenceServiceList';
  static String description = 'description';
  static String key = 'presence';
}
