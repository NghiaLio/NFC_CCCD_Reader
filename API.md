# API reference — `nfc_cccd_reader`

Tài liệu này mô tả các API Dart công khai được export từ `package:nfc_cccd_reader/nfc_cccd_reader.dart`.

## Khởi tạo reader

```dart
final reader = NfcCccdReader(
  logSink: (message) => debugPrint(message), // không bắt buộc
  connectTimeout: const Duration(seconds: 20),
);
```

| Tham số | Kiểu | Mặc định | Mô tả |
|---|---|---:|---|
| `logSink` | `void Function(String)?` | `null` | Nhận log đã được ẩn danh; không chứa PII, CAN hoặc chữ ký thật. |
| `connectTimeout` | `Duration` | `20 giây` | Thời gian tối đa chờ kết nối thẻ NFC. |

## `NfcCccdReader`

| API | Kiểu trả về | Mô tả |
|---|---|---|
| `checkAvailability()` | `Future<NfcAvailabilityStatus>` | Kiểm tra trạng thái NFC của thiết bị. |
| `read(input, {onStage})` | `Future<NfcReadResult>` | Đọc một phiên chip MRTD; lỗi được ném dưới dạng `NfcFailure`. |
| `stageStream` | `Stream<NfcReadStage>` | Stream broadcast các mốc tiến trình của phiên đọc. Khi lỗi, stream đóng kèm lỗi `NfcFailure`. |
| `cancel()` | `Future<void>` | Hủy phiên đọc đang chạy và ngắt kết nối NFC. |
| `dispose()` | `void` | Đóng stream nội bộ; gọi khi không còn sử dụng reader. |

### Callback tiến trình

```dart
final result = await reader.read(
  NfcReadInput.paceFromCccdNumber('001099012345'),
  onStage: (stage) {
    print(stage.progressValue);
  },
);
```

`onStage` và `stageStream` đều phát các giá trị `NfcReadStage`:

| Stage | `progressValue` | Ý nghĩa |
|---|---:|---|
| `waitingForCard` | `0.25` | Đang chờ thẻ. |
| `authenticating` | `0.50` | Đang thiết lập xác thực PACE/BAC. |
| `reading` | `0.75` | Đang đọc Data Group. |
| `validating` | `0.95` | Đang hoàn tất/đối chiếu dữ liệu đọc được. |

## `NfcReadInput`

Đầu vào cho một phiên đọc. Các factory kiểm tra dữ liệu và ném `ArgumentError` nếu không hợp lệ.

| Factory / helper | Mô tả |
|---|---|
| `NfcReadInput.pace(can: String)` | Tạo phiên PACE; `can` phải có đúng 6 chữ số. |
| `NfcReadInput.paceFromCccdNumber(String cccdNumber)` | Tạo phiên PACE từ CCCD 12 số; package tự lấy 6 số cuối làm CAN. |
| `NfcReadInput.bac(documentNumber:, dateOfBirth:, dateOfExpiry:)` | Tạo input BAC cho giấy tờ ICAO. BAC hiện là stub và khi đọc sẽ trả lỗi `bacFailed`. |
| `NfcReadInput.isValidCan(String)` | Kiểm tra CAN gồm đúng 6 chữ số. |
| `NfcReadInput.isValidCccdNumber(String)` | Kiểm tra số CCCD gồm đúng 12 chữ số. |

Các thuộc tính đọc được: `mode`, `can`, `documentNumber`, `dateOfBirth`, `dateOfExpiry`.

## `NfcReadResult`

Kết quả của `read()`. Các trường dữ liệu thẻ có thể là `null` nếu thẻ không công bố hoặc không đọc được Data Group tương ứng.

| Trường | Kiểu | Nguồn / ý nghĩa |
|---|---|---|
| `idNumber` | `String?` | Số định danh từ DG1/MRZ. |
| `fullName` | `String?` | Họ tên từ DG1/MRZ. |
| `dateOfBirth` | `DateTime?` | Ngày sinh từ DG1/MRZ. |
| `dateOfExpiry` | `DateTime?` | Ngày hết hạn từ DG1/MRZ. |
| `gender` | `NfcGender?` | Giới tính đã chuẩn hóa. |
| `nationality` | `String?` | Mã quốc tịch ICAO alpha-3, ví dụ `VNM`. |
| `faceImageBytes` | `Uint8List?` | Ảnh khuôn mặt từ DG2. |
| `extendedData` | `Map<String, String>?` | Dữ liệu đặc thù CCCD từ DG13, như quê quán, dân tộc, tôn giáo, thông tin gia đình, nơi thường trú. Không lặp lại các trường DG1. |
| `aaChallenge` | `Uint8List?` | Nonce gửi tới chip khi Active Authentication. |
| `aaSignature` | `Uint8List?` | Chữ ký phản hồi từ chip. |
| `aaPublicKeyBytes` | `Uint8List?` | Public key từ DG15 để bên thứ ba xác minh chữ ký. |
| `aaAlgorithm` | `String?` | Thuật toán khóa, `RSA` hoặc `EC`. |
| `aaStatus` | `AaEvidenceStatus` | Trạng thái thu thập bằng chứng Active Authentication. |
| `isChipAuthenticityVerified` | `bool` | Trạng thái Passive Authentication; hiện luôn là `false` vì package chưa triển khai xác minh SOD/CSCA. |
| `warnings` | `List<String>` | Các cảnh báo không-fatal, ví dụ một DG được công bố nhưng đọc lỗi. |

## Trạng thái và lỗi

| Kiểu | Giá trị |
|---|---|
| `NfcAvailabilityStatus` | `available`, `disabled`, `notSupported` |
| `NfcSessionMode` | `pace`, `bac` |
| `NfcGender` | `male`, `female`, `unspecified` |
| `AaEvidenceStatus` | `notSupported`, `captured`, `failed` |
| `NfcFailureType` | `timeout`, `tagLost`, `nfcDisabled`, `wrongCan`, `paceFailed`, `bacFailed`, `dgMissing`, `activeAuthFailed`, `unknown` |

Lỗi từ luồng NFC được ném dưới dạng:

```dart
try {
  await reader.read(input);
} on NfcFailure catch (error) {
  print(error.type);
  print(error.message); // có thể null
}
```

`NfcFailure` có hai thuộc tính: `type` (`NfcFailureType`) và `message` (`String?`).

## Extensions hỗ trợ hiển thị

| Extension | API | Kết quả |
|---|---|---|
| Trên `NfcReadStage` | `progressValue` | Giá trị progress từ `0.25` đến `0.95`. |
| Trên `NfcFailureType` | `displayMessage` | Thông điệp lỗi mặc định bằng tiếng Việt. |
| Trên `NfcFailureType` | `isRecoverable` | Có nên cho người dùng thử lại ngay hay không. |
| Trên `NfcGender` | `label` | Nhãn tiếng Việt: `Nam`, `Nữ`, `Không xác định`. |
| Trên `String` | `nationalityLabel` | `VNM` thành `Việt Nam`; các mã khác giữ nguyên. |

## `NfcRepository` (dành cho DI/test)

Interface này được export để ứng dụng có thể mock hoặc thay thế implementation:

```dart
abstract interface class NfcRepository {
  Future<NfcAvailabilityStatus> checkAvailability();
  Future<NfcReadResult> readChip(
    NfcReadInput input, {
    void Function(NfcReadStage stage)? onStage,
  });
  Future<void> cancel();
}
```

> Khuyến nghị app thông thường dùng `NfcCccdReader`; `NfcRepository` phù hợp cho dependency injection và kiểm thử.
