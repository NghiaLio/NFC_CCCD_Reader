import '../entities/nfc_read_input.dart';
import '../entities/nfc_read_result.dart';
import '../entities/nfc_trace_event.dart';
import '../enums/nfc_availability_status.dart';
import '../enums/nfc_read_stage.dart';

/// Interface — cho phép app tiêu thụ tự mock trong test mà không cần thiết bị
/// NFC thật, hoặc tự implement lại nếu muốn thay đổi hành vi.
abstract interface class NfcRepository {
  Future<NfcAvailabilityStatus> checkAvailability();

  Future<NfcReadResult> readChip(
    NfcReadInput input, {
    void Function(NfcReadStage stage)? onStage,
    void Function(NfcTraceEvent event)? onTrace,
  });

  Future<void> cancel();
}
