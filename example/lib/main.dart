import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nfc_cccd_reader/nfc_cccd_reader.dart';

void main() => runApp(const NfcExampleApp());

class NfcExampleApp extends StatelessWidget {
  const NfcExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'nfc_cccd_reader example',
      home: NfcScanExamplePage(),
    );
  }
}

class NfcScanExamplePage extends StatefulWidget {
  const NfcScanExamplePage({super.key});

  @override
  State<NfcScanExamplePage> createState() => _NfcScanExamplePageState();
}

class _NfcScanExamplePageState extends State<NfcScanExamplePage> {
  // Package KHÔNG còn logSink string — thay vào đó app hứng `traceStream`
  // (breadcrumb đã sanitize) và tự log/đẩy lên Sentry.
  final _reader = NfcCccdReader();
  final _cccdController = TextEditingController();

  late final StreamSubscription<NfcTraceEvent> _traceSub;

  NfcReadStage? _stage;
  NfcReadResult? _result;
  String? _errorMessage;
  bool _isScanning = false;
  final List<String> _logs = [];

  @override
  void initState() {
    super.initState();
    _traceSub = _reader.traceStream.listen(_onTrace);
  }

  @override
  void dispose() {
    _traceSub.cancel();
    _reader.dispose();
    _cccdController.dispose();
    super.dispose();
  }

  Future<void> _scan(String cccdNumber) async {
    final availability = await _reader.checkAvailability();
    if (availability != NfcAvailabilityStatus.available) {
      setState(() => _errorMessage = 'NFC không khả dụng: $availability');
      return;
    }

    setState(() {
      _isScanning = true;
      _errorMessage = null;
      _result = null;
      _logs.add('--- Bắt đầu quét: $cccdNumber ---');
    });

    try {
      final input = NfcReadInput.paceFromCccdNumber(cccdNumber);
      final result = await _reader.read(
        input,
        onStage: (stage) => setState(() => _stage = stage),
      );
      _logResultSummary(result);
      setState(() => _result = result);
    } on NfcFailure catch (failure) {
      // Log metadata (sessionId + type + errorDetails) — không lộ PII.
      final logMsg = '[FAIL ${failure.sessionId}] ${failure.type.name} '
          '${failure.errorDetails}';
      debugPrint(logMsg);
      setState(() {
        _logs.add(logMsg);
        _errorMessage = _failureMessage(failure.type);
      });
    } on ArgumentError catch (e) {
      // App tự map tên trường lỗi (.name) sang thông điệp ngôn ngữ riêng.
      final logMsg = '[INPUT ERROR] ${e.name}';
      debugPrint(logMsg);
      setState(() {
        _logs.add(logMsg);
        _errorMessage = _inputErrorMessage(e.name);
      });
    } finally {
      setState(() => _isScanning = false);
    }
  }

  /// Breadcrumb từ package (đã sanitize: chỉ metadata, không PII).
  /// Trong production: gom thêm OS/model thiết bị rồi đẩy lên
  /// Sentry/Crashlytics, nhóm theo [NfcTraceEvent.sessionId].
  void _onTrace(NfcTraceEvent e) {
    final msg = '[TRACE ${e.sessionId}] ${e.step.name} '
        '(${e.elapsed.inMilliseconds}ms'
        '${e.sw1 != null ? ', SW ${e.sw1!.toRadixString(16)}${e.sw2!.toRadixString(16)}' : ''}'
        '${e.dataLengthBytes != null ? ', ${e.dataLengthBytes}B' : ''}'
        '${e.detail != null ? ', ${e.detail}' : ''})';
    debugPrint(msg);
    setState(() => _logs.add(msg));
  }

  String _maskIdNumber(String idNumber) {
    if (idNumber.length < 6) return idNumber;
    final first3 = idNumber.substring(0, 3);
    final last3 = idNumber.substring(idNumber.length - 3);
    return '$first3••••••$last3';
  }

  /// Log CHỈ metadata (không giá trị PII): presence, độ dài, mã — không in
  /// tên/số định danh/nội dung DG13 theo đúng guardrail của package.
  void _logResultSummary(NfcReadResult result) {
    final summary = [
      '================ NFC read result ================',
      'sessionId            : ${result.sessionId}',
      'idNumber present     : ${result.idNumber != null}',
      'fullName present     : ${result.fullName != null}',
      'dateOfBirth          : ${result.dateOfBirth}',
      'dateOfExpiry         : ${result.dateOfExpiry}',
      'gender               : ${result.gender}',
      'nationality          : ${result.nationality}',
      'faceImageBytes       : ${result.faceImageBytes?.lengthInBytes ?? 0} bytes',
      'extendedData fields  : ${result.extendedData?.keys.join(', ') ?? '-'}',
      'aaStatus             : ${result.aaStatus}',
      'aaAlgorithm          : ${result.aaAlgorithm ?? '-'}',
      'aaChallenge bytes    : ${result.aaChallenge?.lengthInBytes ?? 0}',
      'aaSignature bytes    : ${result.aaSignature?.lengthInBytes ?? 0}',
      'warnings             : ${result.warnings.map((w) => w.type.name).join(', ')}',
      '===================================================',
    ].join('\n');
    debugPrint(summary);
    setState(() => _logs.add(summary));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Đọc CCCD qua NFC')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _cccdController,
              keyboardType: TextInputType.number,
              maxLength: 12,
              decoration: const InputDecoration(
                labelText: 'Số CCCD (12 số)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            if (_isScanning) ...[
              LinearProgressIndicator(value: _stage?.progressValue),
              const SizedBox(height: 8),
              Text('Đang quét: ${_stage?.name ?? '...'}'),
              TextButton(onPressed: _reader.cancel, child: const Text('Huỷ')),
            ],
            if (_errorMessage != null)
              Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.red),
              ),
            if (_result != null) ...[
              const Divider(height: 32),
              if (_result!.faceImageBytes != null)
                  Center(
                      child: Image.memory(_result!.faceImageBytes!, height: 160)),
              const SizedBox(height: 8),
              Text('Họ tên: ${_result!.fullName ?? '-'}'),
              Text(
                'Số định danh: '
                '${_result!.idNumber != null ? _maskIdNumber(_result!.idNumber!) : '-'}',
              ),
              Text('Ngày sinh: ${_result!.dateOfBirth ?? '-'}'),
              Text('Ngày hết hạn: ${_result!.dateOfExpiry ?? '-'}'),
              Text('Giới tính: ${_result!.gender != null ? _genderLabel(_result!.gender!) : '-'}'),
              Text('Quốc tịch: ${_result!.nationality ?? '-'}'),
              if (_result!.extendedData != null &&
                  _result!.extendedData!.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text(
                  'Dữ liệu mở rộng (DG13):',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                for (final entry in _result!.extendedData!.entries)
                  Text('  ${entry.key}: ${entry.value}'),
              ],
              const SizedBox(height: 8),
              Text('Trạng thái Active Authentication: ${_result!.aaStatus}'),
              if (_result!.aaAlgorithm != null)
                Text('Thuật toán AA: ${_result!.aaAlgorithm}'),
              Text(
                'Xác thực chip (Passive Auth): '
                '${_result!.isChipAuthenticityVerified}',
              ),
              if (_result!.warnings.isNotEmpty)
                Text('Cảnh báo: '
                    '${_result!.warnings.map((w) => _warningLabel(w.type)).join(', ')}'),
            ],
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _isScanning ? null : () => _scan(_cccdController.text),
              child: const Text('Bắt đầu quét'),
            ),
            const Divider(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Live Logs', style: TextStyle(fontWeight: FontWeight.bold)),
                TextButton(
                  onPressed: () => setState(() => _logs.clear()),
                  child: const Text('Clear'),
                ),
              ],
            ),
            Container(
              height: 250,
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(8),
              ),
              child: ListView.builder(
                padding: const EdgeInsets.all(8),
                itemCount: _logs.length,
                itemBuilder: (context, index) {
                  return Text(
                    _logs[index],
                    style: const TextStyle(
                      color: Colors.greenAccent,
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// App tự map enum/mã sang thông điệp ngôn ngữ riêng — lib không kèm string UI.
String _failureMessage(NfcFailureType type) => switch (type) {
      NfcFailureType.timeout => 'Không tìm thấy thẻ, vui lòng thử lại',
      NfcFailureType.tagLost => 'Mất kết nối với thẻ, giữ yên thẻ và thử lại',
      NfcFailureType.nfcDisabled => 'NFC đang tắt',
      NfcFailureType.wrongCan => 'Số CCCD không đúng, vui lòng kiểm tra lại',
      NfcFailureType.paceFailed => 'Không thiết lập được phiên đọc an toàn',
      NfcFailureType.bacFailed => 'Không đọc được giấy tờ này qua BAC',
      NfcFailureType.dgMissing => 'Thẻ thiếu dữ liệu cần thiết',
      NfcFailureType.activeAuthFailed => 'Xác thực chip thất bại',
      NfcFailureType.unknown => 'Có lỗi xảy ra, vui lòng thử lại',
    };

String _genderLabel(NfcGender gender) => switch (gender) {
      NfcGender.male => 'Nam',
      NfcGender.female => 'Nữ',
      NfcGender.unspecified => 'Không xác định',
    };

String _warningLabel(NfcWarningType type) => switch (type) {
      NfcWarningType.idNumberMissing => 'Không đọc được số định danh',
      NfcWarningType.dg1NotDeclared => 'Thẻ không có DG1',
      NfcWarningType.dg1ReadFailed => 'Lỗi đọc DG1',
      NfcWarningType.dg2NotDeclared => 'Thẻ không có DG2 (ảnh)',
      NfcWarningType.dg2NoImage => 'DG2 không có ảnh',
      NfcWarningType.dg2ReadFailed => 'Lỗi đọc DG2 (ảnh)',
      NfcWarningType.dg13Empty => 'DG13 trống',
      NfcWarningType.dg13ReadOrParseFailed => 'Lỗi đọc DG13',
      NfcWarningType.aaFailed => 'Không lấy được Active Authentication',
    };

/// Map tên trường lỗi (`.name` của `ArgumentError`) sang thông điệp riêng —
/// lib chỉ trả tên trường, không kèm text UI.
String _inputErrorMessage(String? field) => switch (field) {
      'can' => 'CAN phải gồm đúng 6 chữ số',
      'cccdNumber' => 'Số CCCD phải gồm đúng 12 chữ số',
      'documentNumber' => 'Số giấy tờ không được để trống',
      _ => 'Dữ liệu nhập không hợp lệ',
    };
