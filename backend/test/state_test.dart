import 'package:test/test.dart';
import 'package:aerodesk_backend/security.dart';
import 'package:aerodesk_backend/state.dart';

void main() {
  test('new workspace has an owner but no business records', () {
    final state = emptyWorkspace('01k@01k.com');
    expect(records(state['users']).single['email'], '01k@01k.com');
    for (final key in [
      'bookings',
      'customers',
      'quotes',
      'sales',
      'refunds',
      'cases',
      'passportServices',
      'ledger',
      'walletTransactions',
      'audit',
      'companyAssets'
    ]) {
      expect(records(state[key]), isEmpty, reason: key);
    }
    for (final key in [
      'products',
      'sales',
      'purchases',
      'suppliers',
      'customers',
      'expenses',
      'audit',
      'companyAssets'
    ]) {
      expect(records(asObject(state['grocery'])[key]), isEmpty, reason: key);
    }
    expect(records(asObject(state['tableColumns'])['bookings']), isEmpty);
    expect(records(asObject(state['tableColumns'])['products']), isEmpty);
    expect(records(state['customTables']), isEmpty);
  });

  test('new password uses a salted hash', () {
    final first = hashPassword('a sufficiently long test password');
    final second = hashPassword('a sufficiently long test password');
    expect(first, isNot(second));
    expect(
        verifyPassword(
            'a sufficiently long test password', first, 'pbkdf2-sha256'),
        isTrue);
    expect(verifyPassword('wrong', first, 'pbkdf2-sha256'), isFalse);
  });

  test('legacy hash remains verifiable', () {
    expect(verifyPassword('legacy-test', sha256Hex('legacy-test'), 'sha256'),
        isTrue);
    expect(
        verifyPassword('wrong', sha256Hex('legacy-test'), 'sha256'), isFalse);
  });
}
