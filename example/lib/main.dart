import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  NfcParsedResult? _result;
  NfcRawResult? _rawResult;
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

  /// Quét và phân tích cú pháp dữ liệu sang [NfcParsedResult]
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
      _rawResult = null;
      _logs.add('--- Bắt đầu quét Parsed: $cccdNumber ---');
    });

    try {
      final input = NfcReadInput.paceFromCccdNumber(cccdNumber);
      final result = await _reader.readParsed(
        input,
        onStage: (stage) => setState(() => _stage = stage),
      );
      _logResultSummary(result);
      if (result.raw != null) {
        _logRawResultSummary(result.raw!);
      }
      setState(() {
        _result = result;
        _rawResult = result.raw;
      });
    } on NfcFailure catch (failure) {
      final logMsg = '[FAIL ${failure.sessionId}] ${failure.type.name} '
          '${failure.errorDetails}';
      debugPrint(logMsg);
      setState(() {
        _logs.add(logMsg);
        _errorMessage = _failureMessage(failure.type);
      });
    } on ArgumentError catch (e) {
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

  /// Quét thuần dữ liệu thô (raw bytes / chuỗi Base64) sang [NfcRawResult]
  Future<void> _scanRaw(String cccdNumber) async {
    final availability = await _reader.checkAvailability();
    if (availability != NfcAvailabilityStatus.available) {
      setState(() => _errorMessage = 'NFC không khả dụng: $availability');
      return;
    }

    setState(() {
      _isScanning = true;
      _errorMessage = null;
      _result = null;
      _rawResult = null;
      _logs.add('--- Bắt đầu quét Raw Data (Backend payload): $cccdNumber ---');
    });

    try {
      final input = NfcReadInput.paceFromCccdNumber(cccdNumber);
      final rawResult = await _reader.readRaw(
        input,
        onStage: (stage) => setState(() => _stage = stage),
      );
      _logRawResultSummary(rawResult);
      if (rawResult.parsed != null) {
        _logResultSummary(rawResult.parsed!);
      }
      setState(() {
        _rawResult = rawResult;
        _result = rawResult.parsed;
      });
    } on NfcFailure catch (failure) {
      final logMsg = '[FAIL ${failure.sessionId}] ${failure.type.name} '
          '${failure.errorDetails}';
      debugPrint(logMsg);
      setState(() {
        _logs.add(logMsg);
        _errorMessage = _failureMessage(failure.type);
      });
    } on ArgumentError catch (e) {
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

  /// Log kết quả đã parse (ParsedResult)
  void _logResultSummary(NfcParsedResult result) {
    final summary = [
      '================ NFC PARSED RESULT ===============',
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

  /// Log kết quả dữ liệu thô (RawResult)
  void _logRawResultSummary(NfcRawResult raw) {
    String preview(String? str) {
      if (str == null) return 'null';
      if (str.length <= 30) return str;
      return '${str.substring(0, 15)}...${str.substring(str.length - 10)} (${str.length} chars)';
    }

    final summary = [
      '================= NFC RAW RESULT =================',
      'sessionId            : ${raw.sessionId}',
      'dg1 (Base64)         : ${preview(raw.dg1)} (${raw.dg1Bytes?.lengthInBytes ?? 0} bytes)',
      'sod (Base64)         : ${preview(raw.sod)} (${raw.sodBytes?.lengthInBytes ?? 0} bytes)',
      'dg13 (Base64)        : ${preview(raw.dg13)} (${raw.dg13Bytes?.lengthInBytes ?? 0} bytes)',
      'dg2 (Base64)         : ${preview(raw.dg2)} (${raw.dg2Bytes?.lengthInBytes ?? 0} bytes)',
      'dg14 (Base64)        : ${preview(raw.dg14)} (${raw.dg14Bytes?.lengthInBytes ?? 0} bytes)',
      'dg15 (Base64)        : ${preview(raw.dg15)} (${raw.dg15Bytes?.lengthInBytes ?? 0} bytes)',
      'com (Base64)         : ${preview(raw.com)} (${raw.comBytes?.lengthInBytes ?? 0} bytes)',
      'aaStatus             : ${raw.aaStatus.name}',
      'aaChallenge bytes    : ${raw.aaChallenge?.lengthInBytes ?? 0}',
      'aaSignature bytes    : ${raw.aaSignature?.lengthInBytes ?? 0}',
      'warnings             : ${raw.warnings.map((w) => w.type.name).join(', ')}',
      '===================================================',
    ].join('\n');
    debugPrint(summary);
    setState(() => _logs.add(summary));
  }

  Widget _rawItem(String name, String? base64Str, int? bytes) {
    final hasData = base64Str != null && base64Str.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 55,
            child: Text(
              name,
              style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'monospace'),
            ),
          ),
          Icon(
            hasData ? Icons.check_circle : Icons.remove_circle_outline,
            size: 16,
            color: hasData ? Colors.green : Colors.grey,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              hasData
                  ? '${bytes ?? 0} B | ${base64Str.substring(0, base64Str.length > 25 ? 25 : base64Str.length)}...'
                  : 'Không có dữ liệu',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: hasData ? Colors.black87 : Colors.grey,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
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

            // Hiển thị kết quả Parsed
            if (_result != null) ...[
              const Divider(height: 32),
              if (_result!.faceImageBytes != null)
                Center(
                  child: Image.memory(_result!.faceImageBytes!, height: 160),
                ),
              const SizedBox(height: 8),
              Text('Họ tên: ${_result!.fullName ?? '-'}'),
              Text(
                'Họ tên (có dấu): '
                '${_result!.fullNameWithDiacritics ?? _result!.fullName ?? '-'}',
              ),
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

            // Hiển thị kết quả Raw Data
            if (_rawResult != null) ...[
              const Divider(height: 32),
              Card(
                color: Colors.blueGrey.shade50,
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Raw Data Payload (Backend)',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.indigo,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.copy, size: 20),
                            tooltip: 'Sao chép JSON payload cho Backend',
                            onPressed: () {
                              final jsonString = jsonEncode(_rawResult!.toMap());
                              Clipboard.setData(ClipboardData(text: jsonString));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Đã sao chép JSON payload vào clipboard!'),
                                  duration: Duration(seconds: 2),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                      Text(
                        'Session ID: ${_rawResult!.sessionId}',
                        style: const TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                      const SizedBox(height: 8),
                      _rawItem('dg1', _rawResult!.dg1, _rawResult!.dg1Bytes?.lengthInBytes),
                      _rawItem('sod', _rawResult!.sod, _rawResult!.sodBytes?.lengthInBytes),
                      _rawItem('dg13', _rawResult!.dg13, _rawResult!.dg13Bytes?.lengthInBytes),
                      _rawItem('dg2', _rawResult!.dg2, _rawResult!.dg2Bytes?.lengthInBytes),
                      _rawItem('dg14', _rawResult!.dg14, _rawResult!.dg14Bytes?.lengthInBytes),
                      _rawItem('dg15', _rawResult!.dg15, _rawResult!.dg15Bytes?.lengthInBytes),
                      _rawItem('com', _rawResult!.com, _rawResult!.comBytes?.lengthInBytes),
                      const Divider(),
                      Text('Active Authentication: ${_rawResult!.aaStatus.name}'),
                      if (_rawResult!.warnings.isNotEmpty)
                        Text(
                          'Cảnh báo: ${_rawResult!.warnings.map((w) => _warningLabel(w.type)).join(', ')}',
                          style: const TextStyle(color: Colors.orange),
                        ),
                    ],
                  ),
                ),
              ),
            ],

            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: _isScanning ? null : () => _scan(_cccdController.text),
                    icon: const Icon(Icons.nfc),
                    label: const Text(
                      'Quét (1 lần lấy cả 2)',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: _isScanning ? null : () => _scanRaw(_cccdController.text),
                    icon: const Icon(Icons.data_object, size: 16),
                    label: const Text('API readRaw()'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                'Chỉ cần 1 chạm: Cả 2 API đều tự động trả về đầy đủ cả Parsed UI và Raw Backend Payload.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                textAlign: TextAlign.center,
              ),
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
      NfcWarningType.dg14ReadFailed => 'Lỗi đọc DG14',
      NfcWarningType.sodReadFailed => 'Lỗi đọc EF.SOD',
    };

/// Map tên trường lỗi (`.name` của `ArgumentError`) sang thông điệp riêng —
/// lib chỉ trả tên trường, không kèm text UI.
String _inputErrorMessage(String? field) => switch (field) {
      'can' => 'CAN phải gồm đúng 6 chữ số',
      'cccdNumber' => 'Số CCCD phải gồm đúng 12 chữ số',
      'documentNumber' => 'Số giấy tờ không được để trống',
      _ => 'Dữ liệu nhập không hợp lệ',
    };
