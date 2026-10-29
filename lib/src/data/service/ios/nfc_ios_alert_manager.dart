import 'dart:async';
import 'dart:io' show Platform;

import 'package:dmrtd/dmrtd.dart';

import '../../../domain/entities/nfc_failure.dart';
import '../../../domain/entities/nfc_ios_alert_state.dart';
import '../../../domain/enums/nfc_trace_step.dart';

/// Quản lý chữ và thanh tiến trình hiển thị trên sheet NFC mặc định của iOS.
///
/// Bỏ trùng lặp thông điệp (chỉ cập nhật khi chữ thay đổi) và không bao giờ
/// ném lỗi làm hỏng phiên đọc thẻ.
class NfcIosAlertManager {
  NfcIosAlertManager({
    required NfcProvider nfcProvider,
    NfcIosAlertBuilder? iosAlertBuilder,
  })  : _nfcProvider = nfcProvider,
        _iosAlertBuilder = iosAlertBuilder;

  final NfcProvider _nfcProvider;
  final NfcIosAlertBuilder? _iosAlertBuilder;

  /// Chữ mặc định của dmrtd khi app không cung cấp builder.
  static const defaultIosConnectMessage =
      'Hold your iPhone near the biometric Passport';

  // Tiến độ ước lượng theo bước; DG2 là phần nặng nhất (~15–25KB).
  static const progressByStep = <NfcTraceStep, double>{
    NfcTraceStep.connecting: 0.0,
    NfcTraceStep.connected: 0.05,
    NfcTraceStep.sessionStart: 0.10,
    NfcTraceStep.sessionEstablished: 0.20,
    NfcTraceStep.readEfCom: 0.30,
    NfcTraceStep.readDg1: 0.35,
    NfcTraceStep.readDg13: 0.45,
    NfcTraceStep.readDg2: 0.55,
    NfcTraceStep.readDg14: 0.80,
    NfcTraceStep.readDg15Aa: 0.85,
    NfcTraceStep.readEfSod: 0.90,
    NfcTraceStep.completed: 1.0,
  };

  String? _lastMessage;

  bool get isEnabled => _iosAlertBuilder != null && Platform.isIOS;

  /// Xóa cache tin nhắn cũ khi bắt đầu một phiên mới.
  void reset() {
    _lastMessage = null;
  }

  /// Thông điệp hiển thị khi bắt đầu quét thẻ.
  String getConnectMessage() {
    return messageFor(NfcTraceStep.connecting) ?? defaultIosConnectMessage;
  }

  /// Lấy thông điệp cho một bước cụ thể dựa trên builder của người dùng.
  String? messageFor(NfcTraceStep step, {NfcFailure? failure}) {
    if (!isEnabled) return null;
    return _iosAlertBuilder!(
      NfcIosAlertState(
        step: step,
        progress: progressByStep[step] ?? 0,
        failure: failure,
      ),
    );
  }

  /// Cập nhật chữ trên sheet iOS theo bước hiện tại.
  void updateAlert(NfcTraceStep step) {
    if (step == NfcTraceStep.completed || step == NfcTraceStep.failed) return;
    if (!progressByStep.containsKey(step)) return;

    final msg = messageFor(step);
    if (msg == null || msg == _lastMessage) return;
    _lastMessage = msg;

    unawaited(
      _nfcProvider.setIosAlertMessage(msg).catchError((Object _) {}),
    );
  }

  /// Đóng sheet iOS kèm icon ✓ (thành công) hoặc ✗ (thất bại).
  /// Lỗi ở đây được nuốt an toàn để không đè lên kết quả của phiên đọc.
  Future<void> finishSession({NfcFailure? failure}) async {
    try {
      if (failure == null) {
        await _nfcProvider.disconnect(
          iosAlertMessage: messageFor(NfcTraceStep.completed),
        );
      } else {
        await _nfcProvider.disconnect(
          iosErrorMessage: messageFor(NfcTraceStep.failed, failure: failure),
        );
      }
    } catch (_) {}
  }
}
