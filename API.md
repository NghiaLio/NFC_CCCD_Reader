# API reference — `nfc_cccd_reader`

Tài liệu này mô tả các API Dart công khai được export từ `package:nfc_cccd_reader/nfc_cccd_reader.dart`.

Package **không kèm string hiển thị** — lib chỉ trả enum/mã (vd `NfcFailureType`, `NfcGender`, mã quốc tịch ICAO, `NfcWarningType`). App tự map chúng sang thông điệp bằng ngôn ngữ riêng (i18n) của mình. Chi tiết kỹ thuật cho log/diagnose nằm trong `NfcErrorDetails` và `traceStream` (đã sanitize, không kèm PII).

## Khởi tạo reader

```dart
final reader = NfcCccdReader(
  connectTimeout: const Duration(seconds: 20),
);
```

| Tham số | Kiểu | Mặc định | Mô tả |
|---|---|---:|---|
| `connectTimeout` | `Duration` | `20 giây` | Thời gian tối đa chờ kết nối thẻ NFC. |

## `NfcCccdReader`

| API | Kiểu trả về | Mô tả |
|---|---|---|
| `checkAvailability()` | `Future<NfcAvailabilityStatus>` | Kiểm tra trạng thái NFC của thiết bị. |
| `read(input, {onStage, onTrace})` | `Future<NfcReadResult>` | Đọc một phiên chip MRTD; lỗi được ném dưới dạng `NfcFailure`. |
| `stageStream` | `Stream<NfcReadStage>` | Stream broadcast các mốc tiến trình THÔ của phiên đọc (cho progress bar). |
| `traceStream` | `Stream<NfcTraceEvent>` | Stream broadcast breadcrumb chi tiết từng bước (cho log/Sentry). |
| `cancel()` | `Future<void>` | Hủy phiên đọc đang chạy và ngắt kết nối NFC. |
| `dispose()` | `void` | Đóng stream nội bộ; gọi khi không còn sử dụng reader. |

### Callback tiến trình & tracing

```dart
final result = await reader.read(
  NfcReadInput.paceFromCccdNumber('001099012345'),
  onStage: (stage) => print(stage.progressValue),   // progress UI
  onTrace: (event) => _sendToSentry(event),           // log/diagnose
);
```

`onStage`/`stageStream` phát `NfcReadStage` (mốc thô, cho progress bar):

| Stage | `progressValue` | Ý nghĩa |
|---|---:|---|
| `waitingForCard` | `0.25` | Đang chờ thẻ. |
| `authenticating` | `0.50` | Đang thiết lập xác thực PACE/BAC. |
| `reading` | `0.75` | Đang đọc Data Group. |
| `validating` | `0.95` | Đang hoàn tất/đối chiếu dữ liệu đọc được. |

`onTrace`/`traceStream` phát `NfcTraceEvent` (breadcrumb chi tiết, xem mục **Tracing & observability**).

## Tracing & observability

Mỗi lần `read()` tạo một `sessionId` (UUID v4). Mọi `NfcTraceEvent` của phiên đó
kèm `sessionId` để app gom nhóm theo phiên khi log.

`NfcTraceEvent`:

| Trường | Kiểu | Ý nghĩa |
|---|---|---|
| `sessionId` | `String` | Nhóm các event của 1 phiên đọc. |
| `step` | `NfcTraceStep` | Breadcrumb bước hiện tại. |
| `timestamp` | `DateTime` | Thời điểm phát. |
| `elapsed` | `Duration` | Thời gian từ đầu phiên đến bước này. |
| `sw1`, `sw2` | `int?` | Status word 2 byte của APDU gần nhất (khi có). |
| `dataLengthBytes` | `int?` | Độ dài byte của dữ liệu đọc được ở bước này. |
| `detail` | `String?` | Chi tiết kỹ thuật đã sanitize (truncated ≤ 200 ký tự). **Không bao giờ chứa PII.** |

`NfcTraceStep`: `started`, `connecting`, `connected`, `sessionStart`, `sessionEstablished`, `readEfCom`, `readDg1`, `readDg2`, `readDg13`, `readDg15Aa`, `completed`, `failed`.

Cách dùng khuyến nghị — app gom thêm thông tin thiết bị rồi đẩy lên Sentry/Crashlytics:

```dart
reader.traceStream.listen((e) {
  Sentry.captureMessage(
    'nfc_read ${e.step.name}',
    level: SentryLevel.info,
    contexts: {
      'session': e.sessionId,
      'sw': e.sw1 != null ? '${e.sw1!.toRadixString(16)}${e.sw2!.toRadixString(16)}' : null,
      'bytes': e.dataLengthBytes,
      'elapsedMs': e.elapsed.inMilliseconds,
      'detail': e.detail,
      'device': _deviceInfo, // app tự lấy OS/model
    },
  );
});
```

> Tracing chỉ là **metadata** (bước, SW1/SW2, độ dài, thời gian, mã). Không có
> tên, số định danh, ảnh, CAN, key hay nội dung APDU.

## `NfcReadInput`

Đầu vào cho một phiên đọc. Các factory kiểm tra dữ liệu và ném `ArgumentError` nếu không hợp lệ.

| Factory / helper | Mô tả |
|---|---|
| `NfcReadInput.pace(can: String)` | Tạo phiên PACE; `can` phải có đúng 6 chữ số. |
| `NfcReadInput.paceFromCccdNumber(String cccdNumber)` | Tạo phiên PACE từ CCCD 12 số; package dùng 6 số cuối làm CAN và tự động xác thực chéo (cross-verify) 12 số này với ID thật trên chip. |
| `NfcReadInput.bac(documentNumber:, dateOfBirth:, dateOfExpiry:)` | Tạo input BAC cho giấy tờ ICAO. BAC hiện là stub và khi đọc sẽ trả lỗi `bacFailed`. |
| `NfcReadInput.isValidCan(String)` | Kiểm tra CAN gồm đúng 6 chữ số. |
| `NfcReadInput.isValidCccdNumber(String)` | Kiểm tra số CCCD gồm đúng 12 chữ số. |

Các thuộc tính đọc được: `mode`, `can`, `documentNumber`, `dateOfBirth`, `dateOfExpiry`.

## `NfcReadResult`

Kết quả của `read()`. Các trường dữ liệu thẻ có thể là `null` nếu thẻ không công bố hoặc không đọc được Data Group tương ứng.

| Trường | Kiểu | Nguồn / ý nghĩa |
|---|---|---|
| `sessionId` | `String` | Định danh phiên đọc (khớp với `traceStream`). |
| `idNumber` | `String?` | Số định danh từ DG1/MRZ. |
| `fullName` | `String?` | Họ tên từ DG1/MRZ. |
| `dateOfBirth` | `DateTime?` | Ngày sinh từ DG1/MRZ. |
| `dateOfExpiry` | `DateTime?` | Ngày hết hạn từ DG1/MRZ. |
| `gender` | `NfcGender?` | Giới tính đã chuẩn hóa. App tự map nhãn. |
| `nationality` | `String?` | Mã quốc tịch ICAO alpha-3, ví dụ `VNM`. App tự map nhãn. |
| `faceImageBytes` | `Uint8List?` | Ảnh khuôn mặt từ DG2. |
| `extendedData` | `Map<String, String>?` | Dữ liệu đặc thù CCCD từ DG13, như quê quán, dân tộc, tôn giáo, thông tin gia đình, nơi thường trú. Không lặp lại các trường DG1. |
| `aaChallenge` | `Uint8List?` | Nonce gửi tới chip khi Active Authentication. |
| `aaSignature` | `Uint8List?` | Chữ ký phản hồi từ chip. |
| `aaPublicKeyBytes` | `Uint8List?` | Public key từ DG15 để bên thứ ba xác minh chữ ký. |
| `aaAlgorithm` | `String?` | Thuật toán khóa, `RSA` hoặc `EC`. |
| `aaStatus` | `AaEvidenceStatus` | Trạng thái thu thập bằng chứng Active Authentication. |
| `isChipAuthenticityVerified` | `bool` | Trạng thái Passive Authentication; hiện luôn là `false` vì package chưa triển khai xác minh SOD/CSCA. |
| `warnings` | `List<NfcWarning>` | Các cảnh báo không-fatal (structured). |

`NfcWarning`: `type` (`NfcWarningType`) + `detail` (`String?`, kỹ thuật, sanitize). App tự map `NfcWarningType` sang thông điệp hiển thị.

## Trạng thái và lỗi

| Kiểu | Giá trị |
|---|---|
| `NfcAvailabilityStatus` | `available`, `disabled`, `notSupported` |
| `NfcSessionMode` | `pace`, `bac` |
| `NfcGender` | `male`, `female`, `unspecified` |
| `AaEvidenceStatus` | `notSupported`, `captured`, `failed` |
| `NfcFailureType` | `timeout`, `tagLost`, `nfcDisabled`, `wrongCan`, `paceFailed`, `bacFailed`, `dgMissing`, `activeAuthFailed`, `unknown` |
| `NfcWarningType` | `idNumberMissing`, `dg1NotDeclared`, `dg1ReadFailed`, `dg2NotDeclared`, `dg2NoImage`, `dg2ReadFailed`, `dg13Empty`, `dg13ReadOrParseFailed`, `aaFailed` |
| `NfcTraceStep` | `started`, `connecting`, `connected`, `sessionStart`, `sessionEstablished`, `readEfCom`, `readDg1`, `readDg2`, `readDg13`, `readDg15Aa`, `completed`, `failed` |

Lỗi từ luồng NFC được ném dưới dạng `NfcFailure`:

```dart
try {
  await reader.read(input);
} on NfcFailure catch (error) {
  // App tự map error.type sang thông điệp ngôn ngữ riêng.
  print(error.type);                 // NfcFailureType
  print(error.sessionId);            // nhóm trace
  print(error.errorDetails);         // NfcErrorDetails? (SW1/SW2, stage, rootCause, detail)
  if (error.type.isRecoverable) {
    // cho người dùng thử lại
  }
}
```

`NfcFailure` có ba thuộc tính: `type` (`NfcFailureType`), `sessionId` (`String?`), `errorDetails` (`NfcErrorDetails?`).

`NfcErrorDetails`: `sw1`/`sw2` (`int?`, status word APDU), `stage` (`NfcReadStage?`), `rootCause` (`String?`, tên exception gốc), `detail` (`String?`, sanitize ≤ 200 ký tự, không PII).

## Extensions hỗ trợ

| Extension | API | Kết quả |
|---|---|---|
| Trên `NfcReadStage` | `progressValue` | Giá trị progress từ `0.25` đến `0.95`. |
| Trên `NfcFailureType` | `isRecoverable` | Có nên cho người dùng thử lại ngay hay không. |

## `NfcRepository` (dành cho DI/test)

Interface này được export để ứng dụng có thể mock hoặc thay thế implementation:

```dart
abstract interface class NfcRepository {
  Future<NfcAvailabilityStatus> checkAvailability();
  Future<NfcReadResult> readChip(
    NfcReadInput input, {
    void Function(NfcReadStage stage)? onStage,
    void Function(NfcTraceEvent event)? onTrace,
  });
  Future<void> cancel();
}
```

> Khuyến nghị app thông thường dùng `NfcCccdReader`; `NfcRepository` phù hợp cho dependency injection và kiểm thử.
