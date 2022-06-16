import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:at_client_mobile/src/atsign_key.dart';
import 'package:at_utils/at_logger.dart';
import 'package:crypton/crypton.dart';
import 'package:biometric_storage/biometric_storage.dart';
import 'package:flutter_keychain/flutter_keychain.dart';
import 'package:hive/hive.dart';
import 'package:package_info_plus/package_info_plus.dart';

const String _kDefaultKeystoreAccount = '@atsigns';
const int _kDataSchemeVersion = 1;

/// Service to manage keychain entries. This includes saving the
/// encryption keys and secret to keychain
class KeyChainManager {
  static final KeyChainManager _singleton = KeyChainManager._internal();

  static final _logger = AtSignLogger('KeyChainUtil');

  KeyChainManager._internal();

  factory KeyChainManager.getInstance() {
    return _singleton;
  }

  Future<AtClientData?> readAtClientData(
      {bool useSharedStorage = false}) async {
    try {
      final store = await _getAppStorage(useSharedStorage: useSharedStorage);
      final value = await store.read();
      final json = jsonDecode(value ?? '');
      if (json is Map<String, dynamic>) {
        return AtClientData.fromJson(json);
      }
    } catch (e, s) {
      _logger.info('_getAtClientData', e, s);
      print(s);
    }
    return null;
  }

  /// Check app allow sharing atsign or not
  /// @returns 'null' if not define yet
  /// @returns 'true' if use sharing store
  /// @returns 'false' if use internal store
  Future<bool?> isUsingSharedStorage() async {
    final data = await readAtClientData(useSharedStorage: false);
    return data?.config?.useSharedStorage;
  }

  /// Initial setup
  Future<void> initialSetup({required bool useSharedStorage}) async {
    //Bring all key to internal and save in single key if need.
    await _migrateKeychainData();
    //
    if (useSharedStorage) {
      //Init shared storage if it not exiting
      final data = await readAtClientData(useSharedStorage: true);
      if (data == null) {
        _saveAtClientData(
          data: AtClientData(
            config: AtClientDataConfig(
              schemaVersion: _kDataSchemeVersion,
            ),
            keys: [],
          ),
          useSharedStorage: useSharedStorage,
        );
      }
      await enableUsingSharedStorage();
    } else {
      await disableUsingSharedStorage();
    }
  }

  /// Change atsign data to internal store
  Future<bool> disableUsingSharedStorage() async {
    final data = await readAtClientData(useSharedStorage: false);
    if (data != null) {
      if (data.config?.useSharedStorage == false) {
        return false;
      }
      final newConfig = data.config?.copyWith(useSharedStorage: false);
      var newData = data.copyWith(config: newConfig);
      await _saveAtClientData(data: newData, useSharedStorage: false);
      final sharedAtsigns =
          (await readAtClientData(useSharedStorage: true))?.keys ?? [];
      final result = await storeAtSigns(atSigns: sharedAtsigns);
      return result;
    }
    return false;
  }

  /// Change atsign data to internal store
  Future<bool> enableUsingSharedStorage() async {
    //Init shared storage if it not exiting
    final sharedData = await readAtClientData(useSharedStorage: true);
    if (sharedData == null) {
      await _saveAtClientData(
        data: AtClientData(
          config: AtClientDataConfig(
            schemaVersion: _kDataSchemeVersion,
          ),
          keys: [],
        ),
        useSharedStorage: true,
      );
    }
    //
    final data = await readAtClientData(useSharedStorage: false);
    if (data != null) {
      final newConfig = data.config?.copyWith(useSharedStorage: true);
      var newData = data.copyWith(config: newConfig);
      await _saveAtClientData(data: newData, useSharedStorage: false);
      final result = await storeAtSigns(atSigns: data.keys);
      if (result) {
        newData = newData.copyWith(keys: []);
        await _saveAtClientData(data: newData, useSharedStorage: false);
      }
      return result;
    }
    return false;
  }

  /// Function to group all keys saved in old version app to new data
  Future<void> _migrateKeychainData() async {
    //Check if contain new key format
    final clientData = await readAtClientData(useSharedStorage: false);
    final schemaVersion = clientData?.config?.schemaVersion ?? 0;
    final useSharedStorage = clientData?.config?.useSharedStorage ?? false;
    if (schemaVersion == _kDataSchemeVersion) {
      //No need migrate
      return;
    }
    AtClientData migratedData = AtClientData(
      config: AtClientDataConfig(
        schemaVersion: _kDataSchemeVersion,
        useSharedStorage: useSharedStorage,
      ),
      keys: [],
    );
    //Migrate data from version 0 => 1
    if (schemaVersion < 1) {
      //Read old key
      final List<AtsignKey> newAtSignKeys = [];
      try {
        Map<String, dynamic>? keysFromBiometric;
        Map<String, dynamic>? keysFromKeychain;
        try {
          final data =
              await (await BiometricStorage().getStorage('@atsign')).read();
          keysFromBiometric = jsonDecode(data ?? '');
        } catch (e, s) {
          _logger.warning('Read keys from BiometricStorage', e, s);
        }
        try {
          final data = await FlutterKeychain.get(key: '@atsign');
          keysFromKeychain = jsonDecode(data ?? '');
        } catch (e, s) {
          _logger.warning('Read keys from FlutterKeychain', e, s);
        }
        if ((keysFromBiometric ?? <String, dynamic>{}).isNotEmpty) {
          for (var entry in keysFromBiometric!.entries) {
            final key = entry.key;
            final value = entry.value;
            if (value == true) {
              migratedData.defaultAtsign = key;
            }
            final String? pkamPublicKey = await (await BiometricStorage()
                    .getStorage('$key:_pkam_public_key'))
                .read();
            final String? pkamPrivateKey = await (await BiometricStorage()
                    .getStorage('$key:_pkam_private_key'))
                .read();
            final String? encryptionPublicKey = await (await BiometricStorage()
                    .getStorage('$key:_encryption_public_key'))
                .read();
            final String? encryptionPrivateKey = await (await BiometricStorage()
                    .getStorage('$key:_encryption_private_key'))
                .read();
            final String? selfEncryptionKey =
                await (await BiometricStorage().getStorage('$key:_aesKey'))
                    .read();
            final String? hiveSecret =
                await (await BiometricStorage().getStorage('$key:_hive_secret'))
                    .read();
            final String? secret =
                await (await BiometricStorage().getStorage('$key:_secret'))
                    .read();
            final newAtSignKey = AtsignKey(
              name: key,
              pkamPublicKey: pkamPublicKey,
              pkamPrivateKey: pkamPrivateKey,
              encryptionPublicKey: encryptionPublicKey,
              encryptionPrivateKey: encryptionPrivateKey,
              selfEncryptionKey: selfEncryptionKey,
              hiveSecret: hiveSecret,
              secret: secret,
            );
            newAtSignKeys.add(newAtSignKey);
          }
        } else if ((keysFromKeychain ?? <String, dynamic>{}).isNotEmpty) {
          //Read data and migrate from 'FlutterKeychain'
          for (var entry in keysFromKeychain!.entries) {
            final key = entry.key;
            final value = entry.value;
            if (value == true) {
              migratedData.defaultAtsign = key;
            }
            final String? pkamPublicKey =
                await FlutterKeychain.get(key: '$key:_pkam_public_key');
            final String? pkamPrivateKey =
                await FlutterKeychain.get(key: '$key:_pkam_private_key');
            final String? encryptionPublicKey =
                await FlutterKeychain.get(key: '$key:_encryption_public_key');
            final String? encryptionPrivateKey =
                await FlutterKeychain.get(key: '$key:_encryption_private_key');
            final String? selfEncryptionKey =
                await FlutterKeychain.get(key: '$key:_aesKey');
            final String? hiveSecret =
                await FlutterKeychain.get(key: '$key:_hive_secret');
            final String? secret =
                await FlutterKeychain.get(key: '$key:_secret');
            final newAtSignKey = AtsignKey(
              name: key,
              pkamPublicKey: pkamPublicKey,
              pkamPrivateKey: pkamPrivateKey,
              encryptionPublicKey: encryptionPublicKey,
              encryptionPrivateKey: encryptionPrivateKey,
              selfEncryptionKey: selfEncryptionKey,
              hiveSecret: hiveSecret,
              secret: secret,
            );
            newAtSignKeys.add(newAtSignKey);
          }
        }
        migratedData = migratedData.copyWith(keys: newAtSignKeys);
        //Todo: don't remove old data in keychain because still have some apps using old package
        // if ((keysFromBiometric ?? '').isNotEmpty) {
        //   //Read data and migrate 'BiometricStorage'
        //   final keys = jsonDecode(keysFromBiometric!) as Map<String, bool>;
        //   keys.forEach((key, value) async {
        //     await (await BiometricStorage().getStorage('$key:_pkam_public_key'))
        //         .delete();
        //     await (await BiometricStorage().getStorage('$key:_pkam_private_key'))
        //         .delete();
        //     await (await BiometricStorage()
        //             .getStorage('$key:_encryption_public_key'))
        //         .delete();
        //     await (await BiometricStorage()
        //             .getStorage('$key:_encryption_private_key'))
        //         .delete();
        //     await (await BiometricStorage().getStorage('$key:_aesKey')).delete();
        //     await (await BiometricStorage().getStorage('$key:_hive_secret'))
        //         .delete();
        //     await (await BiometricStorage().getStorage('$key:_secret')).delete();
        //   });
        //   await (await BiometricStorage().getStorage('@atsign')).delete();
        // } else if ((keysFromKeychain ?? '').isNotEmpty) {
        //   final keys = jsonDecode(keysFromBiometric!) as Map<String, bool>;
        //   keys.forEach((key, value) async {
        //     await FlutterKeychain.remove(key: '$key:_pkam_public_key');
        //     await FlutterKeychain.remove(key: '$key:_pkam_private_key');
        //     await FlutterKeychain.remove(key: '$key:_encryption_public_key');
        //     await FlutterKeychain.remove(key: '$key:_encryption_private_key');
        //     await FlutterKeychain.remove(key: '$key:_aesKey');
        //     await FlutterKeychain.remove(key: '$key:_hive_secret');
        //     await FlutterKeychain.remove(key: '$key:_secret');
        //   });
        //   await FlutterKeychain.remove(key: '@atsign');
        // }
      } catch (e, s) {
        _logger.warning('Migrate Keychain Data', e, s);
      }
    }
    //Migrate data from version 1 => 2
    if (schemaVersion < 2) {
      //For next update data structure
    }
    await _saveAtClientData(data: migratedData, useSharedStorage: false);
  }

  /// Function to get atsign's key with name
  Future<AtsignKey?> readAtsign({required String name}) async {
    final atSigns = await readAtsigns();
    if(atSigns.isNotEmpty) {
      return atSigns.firstWhere((element) => element.name == name);
    } else {
      return null;
    }
  }

  /// Function to get all atsign item in keychain
  Future<List<AtsignKey>> readAtsigns() async {
    final atClientData = await readAtClientData(useSharedStorage: false);
    final useSharedStorage = atClientData?.config?.useSharedStorage ?? false;
    final data = await readAtClientData(useSharedStorage: useSharedStorage);
    return data?.keys ?? [];
  }

  /// Function to add a new atsign to keychain
  Future<bool> storeAtSign({required AtsignKey atSign}) async {
    final internalAtClientData =
        await readAtClientData(useSharedStorage: false);
    final useSharedStorage =
        internalAtClientData?.config?.useSharedStorage ?? false;
    final atClientData =
        await readAtClientData(useSharedStorage: useSharedStorage);
    if (atClientData != null) {
      final atSigns = atClientData.keys;
      atSigns.removeWhere((element) => element.name == atSign.name);
      atSigns.add(atSign);
      await _saveAtClientData(
          data: atClientData, useSharedStorage: useSharedStorage);
      return true;
    } else {
      return false;
    }
  }

  /// Function to add new atsigns to keychain
  Future<bool> storeAtSigns({required List<AtsignKey> atSigns}) async {
    final internalAtClientData =
        await readAtClientData(useSharedStorage: false);
    final useSharedStorage =
        internalAtClientData?.config?.useSharedStorage ?? false;
    final atClientData =
        await readAtClientData(useSharedStorage: useSharedStorage);
    if (atClientData != null) {
      final oldAtSigns = atClientData.keys;
      //If have no account => make this account is default
      for (var atsign in atSigns) {
        oldAtSigns.removeWhere((element) => element.name == atsign.name);
        oldAtSigns.add(atsign);
      }
      final newAtClientData = atClientData.copyWith(keys: oldAtSigns);
      await _saveAtClientData(
          data: newAtClientData, useSharedStorage: useSharedStorage);
      return true;
    } else {
      return false;
    }
  }

  /// Function to get hive secret from keychain
  Future<List<int>> getHiveSecretFromKeychain(String atsign) async {
    assert(atsign.isNotEmpty);
    List<int> secretAsUint8List = [];
    try {
      var atsignItem = await readAtsign(name: atsign);
      var hiveSecretString = (await readAtsign(name: atsign))?.hiveSecret;
      if (hiveSecretString == null) {
        secretAsUint8List = _generatePersistenceSecret();
        hiveSecretString = String.fromCharCodes(secretAsUint8List);
        atsignItem = atsignItem?.copyWith(
          hiveSecret: hiveSecretString,
        );
        if (atsignItem != null) {
          storeAtSign(atSign: atsignItem);
        }
      } else {
        secretAsUint8List = Uint8List.fromList(hiveSecretString.codeUnits);
      }
    } on Exception catch (exception) {
      _logger.severe(
          'exception in getHiveSecretFromKeychain : ${exception.toString()}');
    }

    return secretAsUint8List;
  }

  /// Fetches list of all the onboarded atsigns
  Future<List<String>> getAtSignListFromKeychain() async {
    final atsigns = await readAtsigns();
    return atsigns.map((e) => e.name).toList();
  }

  /// Function to get atsign secret from keychain
  Future<String?> getSecretFromKeychain(String atsign) async {
    final atsigns = await readAtsign(name: atsign);
    return atsigns?.secret;
  }

  /// Use [getValue]
  @Deprecated("Use getValue")
  Future<String?> getPrivateKeyFromKeyChain(String atsign) async {
    final atsigns = await readAtsign(name: atsign);
    return atsigns?.pkamPrivateKey;
  }

  /// Use [getValue]
  @Deprecated("Use getValue")
  Future<String?> getPublicKeyFromKeyChain(String atsign) async {
    final atsigns = await readAtsign(name: atsign);
    return atsigns?.pkamPublicKey;
  }

  /// Function to save atsign and pkam keys passed to keychain
  Future<bool> storeCredentialToKeychain(String atSign,
      {String? secret, String? privateKey, String? publicKey}) async {
    try {
      final internalAtClientData =
          await readAtClientData(useSharedStorage: false);
      final useSharedStorage =
          internalAtClientData?.config?.useSharedStorage ?? false;
      final atClientData =
          await readAtClientData(useSharedStorage: useSharedStorage);
      final atsigns = atClientData?.keys ?? [];
      if (secret != null) {
        secret = secret.trim().toLowerCase().replaceAll(' ', '');
      }
      final index = atsigns.indexWhere((element) => element.name == atSign);
      if (index >= 0) {
        atsigns[index] = atsigns[index].copyWith(
          secret: secret,
          pkamPrivateKey: privateKey,
          pkamPublicKey: publicKey,
        );
      }
      if (atClientData != null) {
        await _saveAtClientData(
            data: atClientData, useSharedStorage: useSharedStorage);
        return true;
      } else {
        return false;
      }
    } on Exception catch (exception) {
      _logger.severe(
          'exception in storeCredentialToKeychain :${exception.toString()}');
      return false;
    }
  }

  /// Function to save pkam keys for the atsign passed to keychain
  Future<bool> storePkamKeysToKeychain(String atsign,
      {String? privateKey, String? publicKey}) async {
    final internalAtClientData =
        await readAtClientData(useSharedStorage: false);
    final useSharedStorage =
        internalAtClientData?.config?.useSharedStorage ?? false;
    final atClientData =
        await readAtClientData(useSharedStorage: useSharedStorage);
    try {
      final atsigns = atClientData?.keys ?? [];
      final index = atsigns.indexWhere((element) => element.name == atsign);
      if (index >= 0) {
        atsigns[index] = atsigns[index].copyWith(
          pkamPrivateKey: privateKey,
          pkamPublicKey: publicKey,
        );
      } else {
        atsigns.add(AtsignKey(name: atsign).copyWith(
          pkamPrivateKey: privateKey,
          pkamPublicKey: publicKey,
        ));
      }
      atClientData?.keys = atsigns;
      if (atClientData != null) {
        await _saveAtClientData(
            data: atClientData, useSharedStorage: useSharedStorage);
        return true;
      } else {
        return false;
      }
    } catch (e, s) {
      print(e);
      print(s);
      return false;
    }
  }

  /// Function to generate a secure encryption key
  List<int> _generatePersistenceSecret() {
    return Hive.generateSecureKey();
  }

  /// Function to generate an RSA key pair
  RSAKeypair generateKeyPair() {
    var rsaKeypair = RSAKeypair.fromRandom();
    return rsaKeypair;
  }

  /// Function to get cram secret from keychain
  Future<String?> getCramSecret(String atSign) async {
    return getSecretFromKeychain(atSign);
  }

  /// Function to get pkam private key from keychain
  Future<String?> getPkamPrivateKey(String atSign) async {
    final atsigns = await readAtsign(name: atSign);
    return atsigns?.pkamPrivateKey;
  }

  /// Function to get pkam public key from keychain
  Future<String?> getPkamPublicKey(String atSign) async {
    final atsigns = await readAtsign(name: atSign);
    return atsigns?.pkamPublicKey;
  }

  /// Function to get encryption private key from keychain
  Future<String?> getEncryptionPrivateKey(String atSign) async {
    final atsigns = await readAtsign(name: atSign);
    return atsigns?.encryptionPrivateKey;
  }

  /// Function to get encryption public key from keychain
  Future<String?> getEncryptionPublicKey(String atSign) async {
    final atsigns = await readAtsign(name: atSign);
    return atsigns?.encryptionPublicKey;
  }

  /// Function to get self encryption key from keychain
  Future<String?> getSelfEncryptionAESKey(String atSign) async {
    final atsigns = await readAtsign(name: atSign);
    return atsigns?.selfEncryptionKey;
  }

  /// Function to get hive secret from keychain
  Future<List<int>?> getKeyStoreSecret(String atSign) async {
    return getHiveSecretFromKeychain(atSign);
  }

  /// Function to get default atsigns name from keychain
  Future<String?> getAtSign() async {
    final atClientData = await readAtClientData(useSharedStorage: false);
    final defaultAtsign = atClientData?.defaultAtsign;
    if (atClientData?.config?.useSharedStorage == false) {
      final atsignKeys =
          (await readAtClientData(useSharedStorage: false))?.keys ?? [];
      for (var element in atsignKeys) {
        if (element.name == defaultAtsign) {
          return element.name;
        }
      }
      if (atsignKeys.isNotEmpty) return atsignKeys.first.name;
    } else if (atClientData?.config?.useSharedStorage == true) {
      final atsignKeys =
          (await readAtClientData(useSharedStorage: true))?.keys ?? [];
      for (var element in atsignKeys) {
        if (element.name == defaultAtsign) {
          return element.name;
        }
      }
      if (atsignKeys.isNotEmpty) return atsignKeys.first.name;
    }
    return null;
  }

  /// Function to get Map of atsigns from keychain
  Future<Map<String, bool?>> getAtsignsWithStatus() async {
    return await _getAtSignMap();
  }

  /// Function to make the atsign passed as primary
  Future<bool> makeAtSignPrimary(String atsign) async {
    final atClientData = await readAtClientData(useSharedStorage: false);
    if (atClientData != null) {
      atClientData.defaultAtsign = atsign;
      await _saveAtClientData(data: atClientData, useSharedStorage: false);
      return true;
    } else {
      return false;
    }
  }

  /// Function to remove an atsign from list of atsigns and hence, from keychain
  Future<bool> deleteAtSignFromKeychain(String atsign) async {
    final atClientData = await readAtClientData(useSharedStorage: false);
    final useSharedStorage = atClientData?.config?.useSharedStorage ?? false;
    atClientData?.keys.removeWhere((element) => element.name == atsign);
    if (atClientData != null) {
      await _saveAtClientData(
          data: atClientData, useSharedStorage: useSharedStorage);
      return true;
    } else {
      return false;
    }
  }

  /// Function to delete all values related to the atsign passed from keychain
  Future<bool> resetAtSignFromKeychain({required String atsign}) async {
    final atClientData = await readAtClientData(useSharedStorage: false);
    final useSharedStorage = atClientData?.config?.useSharedStorage ?? false;
    atClientData?.keys.removeWhere((element) => element.name == atsign);
    if (atClientData != null) {
      await _saveAtClientData(
          data: atClientData, useSharedStorage: useSharedStorage);
      return true;
    } else {
      return false;
    }
  }

  Future<BiometricStorageFile> _getAppStorage({
    bool useSharedStorage = false,
  }) async {
    String packageName = '';
    try {
      PackageInfo packageInfo = await PackageInfo.fromPlatform();
      packageName = packageInfo.packageName;
    } catch (e, s) {
      _logger.warning('Get PackageInfo', e, s);
    }
    return BiometricStorage().getStorage(
      useSharedStorage
          ? '$_kDefaultKeystoreAccount:shared'
          : '$_kDefaultKeystoreAccount:$packageName',
      options: StorageFileInitOptions(
        authenticationRequired: false,
      ),
    );
  }

  /// Function to save client data
  Future<bool> _saveAtClientData({
    required AtClientData data,
    required bool useSharedStorage,
  }) async {
    try {
      final store = await _getAppStorage(useSharedStorage: useSharedStorage);
      final mapList = jsonEncode(data.toJson());
      await store.write(mapList);
      return true;
    } catch (e, s) {
      _logger.info('_saveClientData', e, s);
      return false;
    }
  }

  // /// Function to save atsigns. It will replace all old keys with new keys passed by param
  // Future<void> _saveAtsigns({
  //   required List<AtsignKey> atsigns,
  // }) async {
  //   var atClientData = await getAtClientData() ??
  //       AtClientData(
  //         config: AtClientDataConfig(schemaVersion: _kDataSchemeVersion),
  //         keys: [],
  //       );
  //   //If have 1 account => make first account is default
  //   if (atsigns.length == 1) {
  //     atsigns[0] = atsigns[0].copyWith(isDefault: true);
  //   }
  //   atClientData = atClientData.copyWith(keys: atsigns);
  //   _saveAtClientData(data: atClientData);
  // }

  /// Function to get Map of atsigns from keychain
  Future<Map<String, bool?>> _getAtSignMap() async {
    final atClientData = await readAtClientData(useSharedStorage: false);
    final atsigns = await readAtsigns();
    final result = <String, bool?>{};
    for (var element in atsigns) {
      result[element.name] = element.name == atClientData?.defaultAtsign;
    }
    return result;
  }
}
