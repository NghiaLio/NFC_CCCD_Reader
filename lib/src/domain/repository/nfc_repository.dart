import '../entities/nfc_parsed_result.dart';
import '../entities/nfc_raw_result.dart';
import '../entities/nfc_read_input.dart';
import '../entities/nfc_trace_event.dart';
import '../enums/nfc_availability_status.dart';
import '../enums/nfc_read_stage.dart';

/// Interface — cho phép app tiêu thụ tự mock trong test mà không cần thiết bị
/// NFC thật, hoặc tự implement lại nếu muốn thay đổi hành vi.
abstract interface class NfcRepository {
  Future<NfcAvailabilityStatus> checkAvailability();

  /// Đọc và phân tích cú pháp (parsed) chip MRTD thành [NfcParsedResult].
  Future<NfcParsedResult> readChip(
    NfcReadInput input, {
    void Function(NfcReadStage stage)? onStage,
    void Function(NfcTraceEvent event)? onTrace,
  });

  /// Tên gọi tường minh hơn cho [readChip]: đọc và phân tích dữ liệu chip.
  Future<NfcParsedResult> readParsedChip(
    NfcReadInput input, {
    void Function(NfcReadStage stage)? onStage,
    void Function(NfcTraceEvent event)? onTrace,
  });

  /// Đọc và trả về dữ liệu thô (raw bytes / Base64) của các Data Group (DG1, DG2,
  /// DG13, DG14, DG15, EF.COM, EF.SOD) để gửi lên Backend xác thực.
  Future<NfcRawResult> readRawChip(
    NfcReadInput input, {
    void Function(NfcReadStage stage)? onStage,
    void Function(NfcTraceEvent event)? onTrace,
  });

  Future<void> cancel();
}
