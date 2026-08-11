import 'package:flutter_test/flutter_test.dart';
import 'package:studyflow/auth/device_identity.dart';

void main() {
  test('device identity is generated once and then restored', () async {
    final store = MemoryDeviceIdentityStore();
    final identity = DeviceIdentity(
      store: store,
      generate: () => 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    );

    final first = await identity.loadOrCreate();
    final second = await identity.loadOrCreate();

    expect(first, 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
    expect(second, first);
    expect(store.writeCount, 1);
  });

  test('invalid persisted device identity fails closed', () async {
    final identity = DeviceIdentity(
      store: MemoryDeviceIdentityStore(
        value: 'not-a-uuid',
      ),
      generate: () => 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
    );

    await expectLater(
      identity.loadOrCreate(),
      throwsA(isA<DeviceIdentityException>()),
    );
  });
}

final class MemoryDeviceIdentityStore implements DeviceIdentityStore {
  MemoryDeviceIdentityStore({this.value});

  String? value;
  int writeCount = 0;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String value) async {
    this.value = value;
    writeCount += 1;
  }
}
