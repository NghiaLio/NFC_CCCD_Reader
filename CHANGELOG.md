## 0.2.0

- **Breaking:** tách bạch UI và logic — lib KHÔNG còn kèm string hiển thị;
  app tự map enum/mã sang thông điệp bằng ngôn ngữ riêng:
  - Xóa extension `NfcGender.label` và `String.nationalityLabel`.
  - Xóa `NfcFailureType.displayMessage`; `NfcFailure` bỏ trường `message`.
  - `NfcReadResult.warnings` đổi từ `List<String>` sang `List<NfcWarning>`
    (structured: `NfcWarningType` + detail kỹ thuật).
  - `NfcCccdReader` bỏ tham số khởi tạo `logSink`.
- **Observability:** thêm tracing cho mỗi phiên đọc:
  - `sessionId` (UUID v4) cho mỗi lần `read()`, có trên cả `NfcReadResult` và
    `NfcFailure`.
  - `NfcCccdReader.traceStream` phát `NfcTraceEvent` breadcrumb từng bước
    (kèm SW1/SW2, độ dài byte, thời gian, chi tiết đã sanitize — KHÔNG kèm PII).
  - `NfcFailure` kèm `NfcErrorDetails` (`sw1`, `sw2`, `stage`, `rootCause`,
    `detail` sanitize).
  - `read()` thêm callback `onTrace` để nhận breadcrumb ngay (ngoài
    `traceStream`).
- Khuyến nghị app dùng `traceStream` + `NfcFailure.errorDetails` để log và
  đẩy lên Sentry/Crashlytics (app tự gom thêm OS/model thiết bị).

## 0.1.1

- Chuẩn hoá dữ liệu đầu ra `NfcReadResult`, không trả raw thô nữa:
  - `gender`: đổi từ ký tự ICAO thô (`String`) sang enum `NfcGender`, kèm
    extension `.label` cho nhãn tiếng Việt.
  - `nationality`: giữ mã ICAO alpha-3 chuẩn (`String`), thêm extension
    `.nationalityLabel` để lấy nhãn hiển thị.
  - `extendedData` (DG13): bỏ các field trùng với top-level
    (idNumber/fullName/dateOfBirth/gender/nationality/dateOfExpiry) — top-level
    (nguồn DG1/MRZ) là nguồn duy nhất cho các giá trị đó.

## 0.1.0

- Phiên bản đầu tiên: đọc CCCD Việt Nam gắn chip / hộ chiếu ICAO 9303 qua NFC
  bằng PACE. Parse DG1 (MRZ), DG2 (ảnh), DG13 (dữ liệu mở rộng CCCD VN),
  DG15 + capture bằng chứng Active Authentication.
- BAC (giấy tờ quốc tế) là stub — luôn ném `NfcFailureType.bacFailed`.
- Passive Authentication (verify SOD/chuỗi CSCA) chưa triển khai —
  `isChipAuthenticityVerified` luôn `false`.
