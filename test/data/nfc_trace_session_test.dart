import 'package:flutter_test/flutter_test.dart';
import 'package:nfc_cccd_reader/nfc_cccd_reader.dart';
import 'package:nfc_cccd_reader/src/data/service/lifecycle/nfc_trace_session.dart';

void main() {
  group('NfcTraceSession', () {
    test('emits trace events with elapsed time and step callback', () {
      final events = <NfcTraceEvent>[];
      final steps = <NfcTraceStep>[];

      final session = NfcTraceSession(
        'test-session-123',
        events.add,
        onStep: steps.add,
      );

      session.emit(NfcTraceStep.connecting);
      session.emit(
        NfcTraceStep.readDg1,
        sw1: 0x90,
        sw2: 0x00,
        bytes: 128,
        detail: '15ms',
      );

      expect(events.length, 2);
      expect(steps, [NfcTraceStep.connecting, NfcTraceStep.readDg1]);

      expect(events[0].sessionId, 'test-session-123');
      expect(events[0].step, NfcTraceStep.connecting);
      expect(events[0].elapsed.inMilliseconds, greaterThanOrEqualTo(0));

      expect(events[1].step, NfcTraceStep.readDg1);
      expect(events[1].sw1, 0x90);
      expect(events[1].sw2, 0x00);
      expect(events[1].dataLengthBytes, 128);
      expect(events[1].detail, '15ms');
    });

    test('sanitize truncates long strings and handles null or empty', () {
      expect(NfcTraceSession.sanitize(null), isNull);
      expect(NfcTraceSession.sanitize('   '), isNull);
      expect(NfcTraceSession.sanitize('short text'), 'short text');

      final longStr = 'a' * 300;
      final sanitized = NfcTraceSession.sanitize(longStr, maxLength: 200);
      expect(sanitized!.length, 201); // 200 chars + '…'
      expect(sanitized.endsWith('…'), isTrue);
    });
  });
}
