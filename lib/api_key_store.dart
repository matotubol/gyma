import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ApiKeyStore {
  static const _storage = FlutterSecureStorage(iOptions: IOSOptions(
    accessibility: KeychainAccessibility.unlocked_this_device,
    synchronizable: false,
  ));
  static const _key = 'gyma.openai.api_key';
  Future<String?> read() => _storage.read(key: _key);
  Future<bool> hasKey() => _storage.containsKey(key: _key);
  Future<void> save(String value) async {
    await _storage.write(key: _key, value: value.trim());
    if (await read() != value.trim()) throw StateError('Keychain did not save the key.');
  }
  Future<void> remove() => _storage.delete(key: _key);
}
