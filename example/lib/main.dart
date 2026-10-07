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
  final _reader = NfcCccdReader(
    logSink: (msg) => debugPrint('[NFC] $msg'),
  );
  final _cccdController = TextEditingController(text: "026204001084");

  NfcReadStage? _stage;
  NfcReadResult? _result;
  String? _errorMessage;
  bool _isScanning = false;

  @override
  void dispose() {
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
    });

    try {
      final input = NfcReadInput.paceFromCccdNumber(cccdNumber);
      final result = await _reader.read(
        input,
        onStage: (stage) => setState(() => _stage = stage),
      );
      _logFullResult(result);
      setState(() => _result = result);
    } on NfcFailure catch (failure) {
      setState(() => _errorMessage = failure.type.displayMessage);
    } on ArgumentError catch (e) {
      setState(() => _errorMessage = e.message?.toString() ?? e.toString());
    } finally {
      setState(() => _isScanning = false);
    }
  }

  String _maskIdNumber(String idNumber) {
    if (idNumber.length < 6) return idNumber;
    final first3 = idNumber.substring(0, 3);
    final last3 = idNumber.substring(idNumber.length - 3);
    return '$first3••••••$last3';
  }

  /// In toàn bộ [NfcReadResult] ra console cho mục đích debug/demo khi test
  /// với thẻ thật. Dữ liệu sinh trắc/chữ ký (ảnh, challenge, signature, public
  /// key) chỉ in độ dài byte — không in raw bytes/hex — theo đúng guardrail
  /// của package (không log giá trị nhạy cảm thật, xem README mục Guardrails).
  void _logFullResult(NfcReadResult result) {
    final extended = result.extendedData;
    final buffer = StringBuffer()
      ..writeln('================ NFC read result ================')
      ..writeln('idNumber           : ${result.idNumber ?? '-'}')
      ..writeln('fullName           : ${result.fullName ?? '-'}')
      ..writeln('dateOfBirth        : ${result.dateOfBirth ?? '-'}')
      ..writeln('dateOfExpiry       : ${result.dateOfExpiry ?? '-'}')
      ..writeln('gender             : ${result.gender?.label ?? '-'}')
      ..writeln(
        'nationality        : ${result.nationality?.nationalityLabel ?? '-'}',
      )
      ..writeln(
        'faceImageBytes     : ${result.faceImageBytes?.lengthInBytes ?? 0} bytes',
      )
      ..writeln('extendedData (DG13):');
    if (extended == null || extended.isEmpty) {
      buffer.writeln('  (không có / thẻ không công bố DG13)');
    } else {
      extended.forEach((key, value) => buffer.writeln('  $key: $value'));
    }
    buffer
      ..writeln('aaStatus           : ${result.aaStatus}')
      ..writeln('aaAlgorithm        : ${result.aaAlgorithm ?? '-'}')
      ..writeln(
        'aaChallenge        : ${result.aaChallenge?.lengthInBytes ?? 0} bytes',
      )
      ..writeln(
        'aaSignature        : ${result.aaSignature?.lengthInBytes ?? 0} bytes',
      )
      ..writeln(
        'aaPublicKeyBytes   : ${result.aaPublicKeyBytes?.lengthInBytes ?? 0} bytes',
      )
      ..writeln(
          'isChipAuthenticityVerified: ${result.isChipAuthenticityVerified}')
      ..writeln(
        'warnings           : ${result.warnings.isEmpty ? '(không có)' : result.warnings.join('; ')}',
      )
      ..write('===================================================');
    debugPrint(buffer.toString());
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
              Text('Giới tính: ${_result!.gender?.label ?? '-'}'),
              Text(
                  'Quốc tịch: ${_result!.nationality?.nationalityLabel ?? '-'}'),
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
                Text('Cảnh báo: ${_result!.warnings.join(', ')}'),
            ],
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _isScanning ? null : () => _scan(_cccdController.text),
              child: const Text('Bắt đầu quét'),
            ),
          ],
        ),
      ),
    );
  }
}
