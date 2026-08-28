# nfc_cccd_reader

Package Flutter headless để đọc CCCD gắn chip Việt Nam và giấy tờ điện tử theo chuẩn ICAO 9303 MRTD qua NFC.

Package không kèm giao diện. Ứng dụng tự xây màn hình nhập CCCD/CAN, hướng dẫn đặt thẻ và hiển thị kết quả theo design system của mình.

## Khả năng hỗ trợ

- Kiểm tra tình trạng NFC trên thiết bị.
- Đọc CCCD gắn chip Việt Nam bằng PACE, với CAN là 6 số cuối của CCCD.
- Đọc DG1 (thông tin MRZ), DG2 (ảnh khuôn mặt), DG13 (dữ liệu mở rộng CCCD), DG15 và bằng chứng Active Authentication khi thẻ hỗ trợ.
- Báo tiến trình đọc bằng callback hoặc `Stream`.
- Chuẩn hóa lỗi NFC thành `NfcFailure` để app không cần xử lý exception thô từ native/MRTD.
- Hỗ trợ `NfcRepository` để mock hoặc dependency injection trong test.

> BAC cho hộ chiếu/giấy tờ quốc tế đã có API đầu vào nhưng hiện chưa được triển khai; lệnh đọc sẽ trả về `NfcFailureType.bacFailed`.

## Cài đặt

```yaml
dependencies:
  nfc_cccd_reader:
    git:
      url: https://github.com/NghiaLio/NFC_CCCD_Reader.git
      ref: main
```

Để bảo đảm build lặp lại được, nên thay `main` bằng tag phát hành hoặc commit
SHA cố định khi tích hợp production:

```yaml
dependencies:
  nfc_cccd_reader:
    git:
      url: https://github.com/NghiaLio/NFC_CCCD_Reader.git
      ref: cdcf2cc435cc016c4a5a955103d926ccacd125cf
```

Sau khi cập nhật `pubspec.yaml`, chạy:

```bash
flutter pub get
```

Import package:

```dart
import 'package:nfc_cccd_reader/nfc_cccd_reader.dart';
```

## Cấu hình Android

Thêm vào `android/app/src/main/AndroidManifest.xml`:

```xml
<uses-feature android:name="android.hardware.nfc" android:required="false" />
<uses-permission android:name="android.permission.NFC" />
```

`flutter_nfc_kit` 3.4.2 dùng `compileSdkVersion 33`. Với Android Gradle Plugin hiện tại, app có thể cần ép module này lên compile SDK mới hơn và cùng JVM target với Java. Thêm vào `android/build.gradle.kts` của app nếu gặp lỗi build liên quan:

```kotlin
gradle.beforeProject {
    if (name == "flutter_nfc_kit") {
        afterEvaluate {
            extensions.findByType(
                com.android.build.gradle.LibraryExtension::class.java,
            )?.compileSdk = 36

            tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>()
                .configureEach {
                    compilerOptions {
                        jvmTarget.set(
                            org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_11,
                        )
                    }
                }
        }
    }
}
```

Điều chỉnh `compileSdk` và JVM target cho phù hợp với toolchain của ứng dụng.

## Cấu hình iOS

Thêm vào `ios/Runner/Info.plist`:

```xml
<key>NFCReaderUsageDescription</key>
<string>Cho phép ứng dụng đọc CCCD hoặc hộ chiếu gắn chip qua NFC.</string>
<key>com.apple.developer.nfc.readersession.iso7816.select-identifiers</key>
<array>
    <string>A0000002471001</string>
</array>
```

Thêm vào `ios/Runner/Runner.entitlements`:

```xml
<key>com.apple.developer.nfc.readersession.formats</key>
<array>
    <string>TAG</string>
</array>
```

Trong Xcode, bật capability **Near Field Communication Tag Reading** cho target Runner. NFC tag reading yêu cầu iPhone 7 trở lên và iOS 13 trở lên.

## Sử dụng nhanh

```dart
final reader = NfcCccdReader(
  logSink: (message) => debugPrint('[NFC] $message'),
);

try {
  final availability = await reader.checkAvailability();
  if (availability != NfcAvailabilityStatus.available) {
    return;
  }

  final result = await reader.read(
    NfcReadInput.paceFromCccdNumber('001099012345'),
    onStage: (stage) {
      debugPrint('Tiến trình: ${(stage.progressValue * 100).round()}%');
    },
  );

  debugPrint(result.fullName);
  debugPrint(result.idNumber);
} on NfcFailure catch (error) {
  debugPrint(error.type.displayMessage);
} finally {
  reader.dispose();
}
```

CCCD Việt Nam không in CAN riêng. Dùng `NfcReadInput.paceFromCccdNumber()` với đúng 12 chữ số CCCD; package sẽ lấy 6 số cuối làm CAN.

## Theo dõi tiến trình bằng Stream

```dart
final subscription = reader.stageStream.listen(
  (stage) => debugPrint(stage.name),
  onError: (Object error) => debugPrint('$error'),
);

try {
  final result = await reader.read(input);
  // Sử dụng result.
} finally {
  await subscription.cancel();
  reader.dispose();
}
```

Các mốc tiến trình gồm: `waitingForCard`, `authenticating`, `reading`, và `validating`.

## Dữ liệu trả về

`read()` trả về `NfcReadResult`. Một số trường phổ biến:

| Trường | Nội dung |
|---|---|
| `idNumber` | Số định danh từ DG1/MRZ. |
| `fullName` | Họ tên từ DG1/MRZ. |
| `dateOfBirth`, `dateOfExpiry` | Ngày sinh và ngày hết hạn. |
| `gender`, `nationality` | Giới tính đã chuẩn hóa và mã quốc tịch ICAO, ví dụ `VNM`. |
| `faceImageBytes` | Bytes ảnh khuôn mặt từ DG2. |
| `extendedData` | Dữ liệu đặc thù DG13, ví dụ quê quán, dân tộc, tôn giáo, thông tin gia đình và nơi thường trú. |
| `aaChallenge`, `aaSignature`, `aaPublicKeyBytes` | Bằng chứng Active Authentication để backend hoặc bên thứ ba xác minh. |
| `warnings` | Cảnh báo không-fatal khi không đọc được một phần dữ liệu. |

Không phải mọi thẻ đều công bố đầy đủ Data Group; các trường tương ứng có thể là `null` mà không làm thất bại toàn bộ phiên đọc.

## Xử lý lỗi

Mọi lỗi của luồng đọc được đưa về `NfcFailure` với `NfcFailureType`:

| Nhóm | Giá trị |
|---|---|
| Thẻ/kết nối | `timeout`, `tagLost` |
| Thiết bị | `nfcDisabled` |
| Xác thực | `wrongCan`, `paceFailed`, `bacFailed`, `activeAuthFailed` |
| Dữ liệu | `dgMissing` |
| Khác | `unknown` |

Có thể dùng `error.type.displayMessage` để lấy thông điệp tiếng Việt mặc định, hoặc `error.type.isRecoverable` để quyết định có nên cho người dùng thử lại.

## Lưu ý bảo mật và giới hạn

- Không ghi CCCD, CAN, ảnh khuôn mặt hoặc dữ liệu PII thật vào log. `logSink` của package chỉ nhận thông tin đã được ẩn danh.
- Ứng dụng nên che số định danh khi hiển thị, ví dụ chỉ giữ ba số đầu và ba số cuối.
- Package chỉ thu thập bằng chứng Active Authentication; không tự xác minh chữ ký đó.
- Passive Authentication (xác minh SOD/chuỗi CSCA) chưa được triển khai, nên `isChipAuthenticityVerified` hiện luôn là `false`.
- Một Data Group đọc lỗi sẽ được ghi vào `warnings` khi có thể; mất kết nối thẻ thực sự vẫn làm phiên đọc thất bại.
- Cấu hình iOS chưa được xác minh trên thiết bị thật trong repository này.
- Package sử dụng fork `HVLoc/dmrtd`; cần rà soát khả năng bảo trì và license trước khi dùng thương mại.

## Tài liệu và kiểm thử

- Danh sách đầy đủ public API: [API.md](API.md).
- Ứng dụng mẫu: [example/lib/main.dart](example/lib/main.dart).

Chạy unit test:

```bash
flutter test
```

Đọc NFC end-to-end vẫn cần thiết bị hỗ trợ NFC và CCCD/thẻ thật để kiểm chứng.
