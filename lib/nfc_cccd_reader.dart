/// Thư viện Flutter headless, framework-agnostic để đọc dữ liệu CCCD gắn chip
/// Việt Nam (và hộ chiếu/eID chuẩn ICAO 9303 MRTD nói chung) qua NFC.
///
/// Package chỉ lo **đọc chip + trả dữ liệu**. Không kèm string hiển thị (app
/// tự map enum/mã sang ngôn ngữ riêng), không tự xác minh, không gửi dữ liệu
/// ra mạng. Tracing (breadcrumb + SW1/SW2, đã sanitize) phát qua `traceStream`.
library nfc_cccd_reader;

// Facade — entry point chính.
export 'src/nfc_cccd_reader_base.dart' show NfcCccdReader;

// Domain types cần thiết ở boundary của app tiêu thụ.
export 'src/domain/entities/nfc_read_input.dart';
export 'src/domain/entities/nfc_read_result.dart';
export 'src/domain/entities/nfc_failure.dart';
export 'src/domain/entities/nfc_error_details.dart';
export 'src/domain/entities/nfc_warning.dart';
export 'src/domain/entities/nfc_trace_event.dart';
export 'src/domain/enums/nfc_availability_status.dart';
export 'src/domain/enums/nfc_failure_type.dart';
export 'src/domain/enums/nfc_gender.dart';
export 'src/domain/enums/nfc_read_stage.dart';
export 'src/domain/enums/nfc_session_mode.dart';
export 'src/domain/enums/nfc_trace_step.dart';
export 'src/domain/enums/nfc_warning_type.dart';
export 'src/domain/enums/aa_evidence_status.dart';

// Tiện ích hành vi/tiến trình (không còn string hiển thị — app tự map i18n).
export 'src/domain/extensions/nfc_failure_x.dart';
export 'src/domain/extensions/nfc_read_stage_x.dart';

// Interface — cho ai muốn tự mock/implement khác (test, DI).
export 'src/domain/repository/nfc_repository.dart';
