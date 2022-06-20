import 'package:at_client/at_client.dart';
import 'package:at_client/src/presence_service/at_presence_service.dart';
import 'package:at_client/src/presence_service/presence_model.dart';
import 'package:test/test.dart';

import 'package:mocktail/mocktail.dart';

Map localKeyStore = {};

class MockAtClientImpl extends Mock implements AtClientImpl {
  @override
  String? getCurrentAtSign() {
    return '@alice';
  }

  @override
  Future<bool> put(AtKey key, dynamic value, {bool isDedicated = false}) {
    localKeyStore.putIfAbsent(key.toString(), () => AtValue().value = value);
    return Future.value(true);
  }

  @override
  Future<AtValue> get(AtKey key, {bool isDedicated = false}) {
    var response;
    if (localKeyStore.containsKey(key.toString())) {
      response = localKeyStore[key.toString()];
    }
    var atValue = AtValue()..value = response;
    return Future.value(atValue);
  }
}

void main() {
  AtClientImpl mockAtClientImpl = MockAtClientImpl();
  group('A group of test to validate presence service', () {
    test('test to set a global presence', () async {
      var presenceService = AtPresenceService(mockAtClientImpl);
      await presenceService.setPresence(Presence(PresenceStatus.available,
          [PresenceServices.message], 'Available for messages only'));
      var response = await presenceService.getPresence();
      expect(response.description, 'Available for messages only');
      expect(response.presenceStatus, PresenceStatus.available);
      expect(response.presenceServicesList, [PresenceServices.message]);
    });

    test('test to set a presence specific to atSign', () async {
      var presenceService = AtPresenceService(mockAtClientImpl);
      await presenceService.setPresence(
          Presence(PresenceStatus.unavailable, [PresenceServices.call],
              'Unavailable for calls'),
          atSign: '@bob');
      var response = await presenceService.getPresence(atSign: '@bob');
      expect(response.description, 'Unavailable for calls');
      expect(response.presenceStatus, PresenceStatus.unavailable);
      expect(response.presenceServicesList, [PresenceServices.call]);
    });
  });
}
