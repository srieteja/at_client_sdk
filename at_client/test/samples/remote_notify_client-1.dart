import 'package:at_client/at_client.dart';
import 'package:uuid/uuid.dart';
import 'test_util.dart';

void main() async {
  final senderAtSign = '@alice';
  final receiverAtSign = '@bob';
  final clientPreference1 = TestUtil.getAlicePreference();
  await AtClientManager.getInstance()
      .setCurrentAtSign(senderAtSign, 'wavi', clientPreference1);
  var notifierId = await getNotifier();
  print('NotifierId : $notifierId');

  var i = 0;
  while (true) {
    // Notifications sending from client-1
    var result = await AtClientManager.getInstance().notificationService.notify(
        NotificationParams.forText('hello from client-1-$i', receiverAtSign,
            strategyEnum: StrategyEnum.latest, notifier: notifierId),
        checkForFinalDeliveryStatus: false);
    print(result);
    i = i + 1;
  }
}

Future<String> getNotifier() async {
  var atKey = AtKey()
    ..key = '_client'
    ..metadata = (Metadata()..isPublic = true);

  try {
    AtValue getResponse =
        await AtClientManager.getInstance().atClient.get(atKey);
    if (getResponse.value != null) {
      return getResponse.value;
    }
  } on AtKeyNotFoundException {
    print('key not found');
  }

  var uuid = Uuid().v4();
  await AtClientManager.getInstance().atClient.put(atKey, uuid);
  return uuid;
}
