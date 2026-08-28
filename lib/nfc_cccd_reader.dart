/// Thư viện Flutter headless, framework-agnostic để đọc dữ liệu CCCD gắn chip
/// Việt Nam (và hộ chiếu/eID chuẩn ICAO 9303 MRTD nói chung) qua NFC.
library nfc_cccd_reader;

// Facade — entry point chính.
export 'src/nfc_cccd_reader_base.dart' show NfcCccdReader;

// Domain types cần thiết ở boundary của app tiêu thụ.
export 'src/domain/entities/nfc_read_input.dart';
export 'src/domain/entities/nfc_read_result.dart';
export 'src/domain/entities/nfc_failure.dart';
export 'src/domain/enums/nfc_availability_status.dart';
export 'src/domain/enums/nfc_failure_type.dart';
export 'src/domain/enums/nfc_gender.dart';
export 'src/domain/enums/nfc_read_stage.dart';
export 'src/domain/enums/nfc_session_mode.dart';
export 'src/domain/enums/aa_evidence_status.dart';

// Tiện ích hiển thị (tuỳ chọn dùng, có thể override message theo i18n riêng).
export 'src/domain/extensions/nfc_failure_x.dart';
export 'src/domain/extensions/nfc_gender_x.dart';
export 'src/domain/extensions/nfc_nationality_x.dart';
export 'src/domain/extensions/nfc_read_stage_x.dart';

// Interface — cho ai muốn tự mock/implement khác (test, DI).
export 'src/domain/repository/nfc_repository.dart';
