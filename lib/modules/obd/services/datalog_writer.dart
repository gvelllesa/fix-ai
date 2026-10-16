import 'dart:async';
import 'dart:io';

/// Datalog data entry matching professional automotive logging fields
class DatalogRow {
  final int timestampMs;
  final double rpm;
  final double boostPsi;
  final double targetBoostPsi;
  final double timingCyl1;
  final bool knockFlag;
  final double lambdaBank1;
  final double stftPct;
  final double iatC;
  final double coolantC;

  const DatalogRow({
    required this.timestampMs,
    required this.rpm,
    required this.boostPsi,
    required this.targetBoostPsi,
    required this.timingCyl1,
    required this.knockFlag,
    required this.lambdaBank1,
    required this.stftPct,
    required this.iatC,
    required this.coolantC,
  });

  String toCsv() =>
      '$timestampMs,${rpm.toStringAsFixed(1)},${boostPsi.toStringAsFixed(2)},${targetBoostPsi.toStringAsFixed(2)},${timingCyl1.toStringAsFixed(2)},${knockFlag ? 1 : 0},${lambdaBank1.toStringAsFixed(3)},${stftPct.toStringAsFixed(2)},${iatC.toStringAsFixed(1)},${coolantC.toStringAsFixed(1)}';
}

/// Asynchronous buffered CSV datalog writer
///
/// Prevents main UI thread stutters and dropped frames during wide-open-throttle (WOT) pulls.
/// Queues rows in a memory buffer and flushes them in batches to disk every 1-2 seconds
/// or when buffer reaches [bufferThreshold] rows.
class DatalogWriter {
  static const String csvHeader =
      'timestamp_ms,rpm,boost_psi,target_boost,timing_cyl1,knock_flag,lambda_bank1,stft_pct,iat_c,coolant_c';

  final File targetFile;
  final int bufferThreshold;
  final Duration flushInterval;

  IOSink? _sink;
  final List<String> _buffer = [];
  Timer? _flushTimer;
  bool _isOpen = false;
  bool _isFlushing = false;
  int _totalWrittenRows = 0;

  int get totalWrittenRows => _totalWrittenRows;
  bool get isOpen => _isOpen;
  int get bufferedRows => _buffer.length;

  DatalogWriter(
    this.targetFile, {
    this.bufferThreshold = 100,
    this.flushInterval = const Duration(seconds: 1),
  });

  /// Opens the datalog file and writes CSV header
  Future<void> open() async {
    if (_isOpen) return;
    _sink = targetFile.openWrite(mode: FileMode.writeOnly);
    _sink!.writeln(csvHeader);
    _isOpen = true;
    _totalWrittenRows = 0;

    _flushTimer = Timer.periodic(flushInterval, (_) => flush());
  }

  /// Buffers a single telemetry row
  void addRow(DatalogRow row) {
    if (!_isOpen) return;
    _buffer.add(row.toCsv());
    _totalWrittenRows++;
    if (_buffer.length >= bufferThreshold && !_isFlushing) {
      unawaited(flush());
    }
  }

  /// Buffers a raw CSV formatted line
  void addRawCsvRow(String csvLine) {
    if (!_isOpen) return;
    _buffer.add(csvLine);
    _totalWrittenRows++;
    if (_buffer.length >= bufferThreshold && !_isFlushing) {
      unawaited(flush());
    }
  }

  /// Flushes all buffered lines to disk
  Future<void> flush() async {
    if (!_isOpen || _sink == null || _buffer.isEmpty || _isFlushing) return;
    _isFlushing = true;
    try {
      final chunk = List<String>.from(_buffer);
      _buffer.clear();
      for (final line in chunk) {
        _sink!.writeln(line);
      }
      await _sink!.flush();
    } catch (_) {
      // Sink error handling
    } finally {
      _isFlushing = false;
    }

    if (_isOpen && _buffer.length >= bufferThreshold) {
      unawaited(flush());
    }
  }

  /// Flushes remaining rows, stops timer, and safely closes the file stream
  Future<void> close() async {
    if (!_isOpen) return;
    _isOpen = false;
    _flushTimer?.cancel();
    _flushTimer = null;

    while (_isFlushing) {
      await Future.delayed(const Duration(milliseconds: 10));
    }

    if (_sink != null) {
      if (_buffer.isNotEmpty) {
        for (final line in _buffer) {
          _sink!.writeln(line);
        }
        _buffer.clear();
      }
      try {
        await _sink!.flush();
      } catch (_) {}
      try {
        await _sink!.close();
      } catch (_) {}
      _sink = null;
    }
  }
}
