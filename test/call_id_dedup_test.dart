import 'package:flutter_test/flutter_test.dart';
import 'package:glcalls/features/recordings/data/datasources/call_sync_datasource.dart';

/// These tests are the contract that prevents the "same call appears twice
/// on the dashboard" / "same number in inbound AND outbound" bugs from
/// silently regressing.
///
/// The contract: same physical call from any sync path → same `call_id`.
/// If any of these tests fail, the dedupe ledger will let duplicates
/// through.
void main() {
  group('CallSyncData.normalizePhoneForId', () {
    test('strips formatting characters', () {
      expect(
        CallSyncData.normalizePhoneForId('+91 98765 43210'),
        '9876543210',
      );
      expect(
        CallSyncData.normalizePhoneForId('(987) 654-3210'),
        '9876543210',
      );
    });

    test('drops country code by keeping last 10 digits', () {
      expect(CallSyncData.normalizePhoneForId('919876543210'), '9876543210');
      expect(CallSyncData.normalizePhoneForId('+919876543210'), '9876543210');
      expect(CallSyncData.normalizePhoneForId('00919876543210'), '9876543210');
    });

    test('returns shorter numbers as-is', () {
      expect(CallSyncData.normalizePhoneForId('1234'), '1234');
    });
  });

  group('CallSyncData.bucketCallTimeToMinute', () {
    test('zeros out seconds and milliseconds', () {
      final t = DateTime.utc(2026, 5, 14, 10, 27, 44, 123);
      final bucketed = CallSyncData.bucketCallTimeToMinute(t);
      expect(bucketed, DateTime.utc(2026, 5, 14, 10, 27));
    });

    test('converts local time to UTC before bucketing', () {
      final local = DateTime(2026, 5, 14, 10, 27, 44, 123);
      final bucketed = CallSyncData.bucketCallTimeToMinute(local);
      expect(bucketed.isUtc, true);
      expect(bucketed.second, 0);
      expect(bucketed.millisecond, 0);
    });
  });

  group('CallSyncData.buildDeterministicCallId — dedupe contract', () {
    test('different phone formats for same call → same id', () {
      final t = DateTime.utc(2026, 5, 14, 10, 27);
      final a = CallSyncData.buildDeterministicCallId(
        phoneNumber: '9876543210',
        callTime: t,
      );
      final b = CallSyncData.buildDeterministicCallId(
        phoneNumber: '+91 98765 43210',
        callTime: t,
      );
      final c = CallSyncData.buildDeterministicCallId(
        phoneNumber: '919876543210',
        callTime: t,
      );
      expect(a, b);
      expect(a, c);
    });

    test('millisecond/second skew within the same minute → same id', () {
      final a = CallSyncData.buildDeterministicCallId(
        phoneNumber: '9876543210',
        callTime: DateTime.utc(2026, 5, 14, 10, 27, 0, 0),
      );
      final b = CallSyncData.buildDeterministicCallId(
        phoneNumber: '9876543210',
        callTime: DateTime.utc(2026, 5, 14, 10, 27, 44, 123),
      );
      final c = CallSyncData.buildDeterministicCallId(
        phoneNumber: '9876543210',
        callTime: DateTime.utc(2026, 5, 14, 10, 27, 59, 999),
      );
      expect(a, b);
      expect(a, c);
    });

    test('direction does NOT change the id (the inbound/outbound dup fix)', () {
      final t = DateTime.utc(2026, 5, 14, 10, 27);
      final inbound = CallSyncData.buildDeterministicCallId(
        phoneNumber: '9876543210',
        callTime: t,
        direction: 'inbound',
      );
      final outbound = CallSyncData.buildDeterministicCallId(
        phoneNumber: '9876543210',
        callTime: t,
        direction: 'outbound',
      );
      expect(inbound, outbound,
          reason: 'A real call has one direction; including it in the hash '
              'creates a phantom duplicate when direction is misdetected.');
    });

    test('different minute → different id (real distinct calls)', () {
      final a = CallSyncData.buildDeterministicCallId(
        phoneNumber: '9876543210',
        callTime: DateTime.utc(2026, 5, 14, 10, 27),
      );
      final b = CallSyncData.buildDeterministicCallId(
        phoneNumber: '9876543210',
        callTime: DateTime.utc(2026, 5, 14, 10, 28),
      );
      expect(a, isNot(b));
    });

    test('different phone → different id', () {
      final t = DateTime.utc(2026, 5, 14, 10, 27);
      final a = CallSyncData.buildDeterministicCallId(
        phoneNumber: '9876543210',
        callTime: t,
      );
      final b = CallSyncData.buildDeterministicCallId(
        phoneNumber: '9876543211',
        callTime: t,
      );
      expect(a, isNot(b));
    });
  });
}
