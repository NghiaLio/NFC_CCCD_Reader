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

## Tích hợp vào project

Package chỉ lo **đọc chip + trả dữ liệu**. UI nhập CCCD, xác minh danh tính, liveness/so khớp khuôn mặt, đối chiếu cơ sở dữ liệu, thu consent và lưu trữ đều do **ứng dụng/hệ thống phía trên** tự triển khai — package không tự làm, không tự xác minh, và không gửi dữ liệu ra mạng.

Thứ tự tích hợp:

1. Thêm dependency + `flutter pub get` (mục Cài đặt).
2. Khai báo native — Cấu hình Android và/hoặc Cấu hình iOS (bắt buộc, không khai báo sẽ không đọc được thẻ).
3. Trong code: `checkAvailability()` → `read(input, onStage: ...)` → dùng `NfcReadResult`, bắt `NfcFailure`, rồi `dispose()` (mục Sử dụng nhanh).
4. Nếu quy trình cần xác minh, chuyển `aaChallenge`/`aaSignature`/`aaPublicKeyBytes` (cùng ảnh DG2 và dữ liệu DG1/DG13) cho hệ thống phía trên để xử lý.

> **Lưu ý trọng tâm:** package trả dữ liệu **đã parse** + bằng chứng **Active Authentication**. Nó **chưa trả raw bytes SOD/các DG**, nên hệ thống phía trên **không làm được Passive Authentication** với output hiện tại — chỉ verify được AA. Nếu quy trình bắt buộc cần PA, cần bổ sung raw data (xem mục Lưu ý bảo mật và giới hạn).

## Cài đặt

```yaml
dependencies:
  nfc_cccd_reader:
    git:
      url: https://github.com/NghiaLio/NFC_CCCD_Reader.git
      ref: main
```

Để bảo đảm build lặp lại được, nên pin bằng **tag phát hành** (khuyến nghị) hoặc
commit SHA cố định khi tích hợp production, thay vì `main`:

```yaml
dependencies:
  nfc_cccd_reader:
    git:
      url: https://github.com/NghiaLio/NFC_CCCD_Reader.git
      ref: v0.1.1   # hoặc một commit SHA cố định
```

> Giao thức MRTD (`dmrtd`) được **vendored trong repo này** tại `third_party/dmrtd`. Khi pin package, toàn bộ `dmrtd` cũng được cố định theo — bạn **không cần** (và không nên) khai báo `dmrtd` riêng trong app.

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

## Xử lý sự cố

| Triệu chứng | Nguyên nhân / cách xử lý |
|---|---|
| `checkAvailability()` trả `disabled` / `notSupported` | NFC đang tắt hoặc thiết bị không hỗ trợ — hướng dẫn người dùng bật NFC. |
| Lỗi `timeout` | Chưa nhận thấy thẻ trong thời gian chờ (mặc định 20s). Giữ thẻ sát vùng NFC rồi thử lại; có thể tăng `connectTimeout` khi tạo `NfcCccdReader`. |
| Lỗi `wrongCan` | Số CCCD/CAN nhập sai. Kiểm tra lại số CCCD 12 số (hoặc 6 số CAN). |
| Lỗi `paceFailed` | Thiết lập phiên PACE thất bại. Xem ghi chú **Tương thích thẻ** bên dưới. |
| Lỗi `tagLost` | Rút thẻ giữa chừng. Giữ yên thẻ đến khi đọc xong. |
| `faceImageBytes` / `extendedData` là `null` | Thẻ không công bố DG2/DG13 — xem `warnings`. Đây không phải lỗi. |
| Build fail liên quan `archive` | Nếu app có package khác ép `archive` xuống <4, thêm `dependency_overrides: archive: ^4.0.9` vào **pubspec của app** (override trong package này không áp dụng cho consumer). |
| iOS không đọc được thẻ | Kiểm tra AID `A0000002471001` trong `Info.plist`, `TAG` trong `Runner.entitlements`, và capability NFC đã bật trong Xcode. |

**Tương thích thẻ (quan trọng):** PACE trong package dùng **EF.CardAccess cố định** phù hợp với thẻ CCCD gắn chip Việt Nam. Nếu cần hỗ trợ thẻ/lô khác có EF.CardAccess khác, lệnh đọc có thể trả `paceFailed`/`wrongCan` dù số CCCD đúng — lúc đó cần hiệu chỉnh EF.CardAccess theo thẻ.

## Lưu ý bảo mật và giới hạn

- Không ghi CCCD, CAN, ảnh khuôn mặt hoặc dữ liệu PII thật vào log. `logSink` của package chỉ nhận thông tin đã được ẩn danh.
- Ứng dụng nên che số định danh khi hiển thị, ví dụ chỉ giữ ba số đầu và ba số cuối.
- Package chỉ thu thập bằng chứng Active Authentication; không tự xác minh chữ ký đó.
- Passive Authentication (xác minh SOD/chuỗi CSCA) chưa được triển khai, nên `isChipAuthenticityVerified` hiện luôn là `false`.
- Một Data Group đọc lỗi sẽ được ghi vào `warnings` khi có thể; mất kết nối thẻ thực sự vẫn làm phiên đọc thất bại.
- Luồng đọc end-to-end đã được kiểm chứng trên thẻ CCCD gắn chip thật. Tỷ lệ đọc thành công phụ thuộc vị trí ăng-ten NFC và từng dòng máy, nên trước khi phát hành hãy tự kiểm thử trên tập thiết bị mục tiêu (nhiều dòng Android + iOS).
- Giao thức MRTD (PACE/AA/Secure Messaging) được **vendored** tại `third_party/dmrtd` (fork `HVLoc/dmrtd`, branch `flutter/3.41.1`, commit `4300157`) để tự kiểm soát, audit và patch được code. Chạy test riêng: `cd third_party/dmrtd && flutter test`.
- License của `dmrtd` là **dual: LGPL v3 / Commercial** (file `LICENSE.LGPL` + `LICENSE.COMMERCIAL` trong `third_party/dmrtd`). Nếu bạn **modify** code dmrtd thì phần sửa phải được chia sẻ theo LGPL; nếu dùng **thương mại** và không muốn ràng buộc LGPL thì liên hệ mua license Commercial. Rà soát trước khi phát hành.

## Tài liệu và kiểm thử

- Danh sách đầy đủ public API: [API.md](API.md).
- Ứng dụng mẫu: [example/lib/main.dart](example/lib/main.dart).

Chạy unit test:

```bash
flutter test
```

Để tự kiểm chứng trên thiết bị/thẻ cụ thể, chạy sample app trong `example/` (cần thiết bị NFC + thẻ CCCD thật).
