import 'dart:io';

import 'package:excel/excel.dart' as excel;
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  runApp(const AnswerSheetScannerApp());
}

class AnswerSheetScannerApp extends StatelessWidget {
  const AnswerSheetScannerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Automated Answer Sheet Scanner & Gradebook',
      theme: ThemeData(
        primarySwatch: Colors.indigo,
        useMaterial3: true,
      ),
      home: const ScannerHomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

int calculateScoreFromKey(List<String> answerKey, List<String> studentAnswers) {
  final totalQuestions = answerKey.length < studentAnswers.length ? answerKey.length : studentAnswers.length;
  int correctAnswers = 0;

  for (int i = 0; i < totalQuestions; i++) {
    final keyAnswer = answerKey[i].trim().toUpperCase();
    final studentAnswer = studentAnswers[i].trim().toUpperCase();

    if (keyAnswer == studentAnswer) {
      correctAnswers++;
    }
  }

  return correctAnswers;
}

String buildResultRemark(int score, int totalQuestions) {
  if (totalQuestions == 0) {
    return 'Failed';
  }

  final percentage = (score / totalQuestions) * 100;
  return percentage >= 60 ? 'Passed' : 'Failed';
}

String buildExportCsv(List<StudentResult> records) {
  final buffer = StringBuffer();
  buffer.writeln('Student Name,Class,Subject,Score,Remarks,Confidence,Scanned At');

  for (final record in records) {
    final studentName = _escapeCsvField(record.studentName);
    final className = _escapeCsvField(record.className);
    final subjectName = _escapeCsvField(record.subjectName);
    final remarks = _escapeCsvField(record.remarks);
    final scannedAt = _escapeCsvField(record.scannedAt);
    final confidence = (record.confidence * 100).round();

    buffer.writeln('$studentName,$className,$subjectName,${record.score},$remarks,$confidence%,$scannedAt');
  }

  return buffer.toString();
}

excel.Excel buildGradebookWorkbook(List<StudentResult> records) {
  final workbook = excel.Excel.createExcel();
  final sheet = workbook['Sheet1'];

  sheet.appendRow([
    excel.TextCellValue('Student Name'),
    excel.TextCellValue('Class'),
    excel.TextCellValue('Subject'),
    excel.TextCellValue('Score'),
    excel.TextCellValue('Remarks'),
    excel.TextCellValue('Confidence'),
    excel.TextCellValue('Scanned At'),
  ]);

  for (final record in records) {
    final confidence = '${(record.confidence * 100).round()}%';
    sheet.appendRow([
      excel.TextCellValue(record.studentName),
      excel.TextCellValue(record.className),
      excel.TextCellValue(record.subjectName),
      excel.IntCellValue(record.score),
      excel.TextCellValue(record.remarks),
      excel.TextCellValue(confidence),
      excel.TextCellValue(record.scannedAt),
    ]);
  }

  return workbook;
}

String buildReviewDecision(double confidence) {
  if (confidence >= 0.85) {
    return 'Auto-approved';
  }
  if (confidence >= 0.7) {
    return 'Monitor';
  }
  return 'Needs review';
}

List<String> parseStudentRoster(String rosterText) {
  final cleaned = rosterText
      .split(RegExp(r'[\n,;]'))
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toList();

  return cleaned;
}

String nextStudentFromRoster(List<String> roster, int index) {
  if (roster.isEmpty) {
    return 'Student';
  }

  if (index >= roster.length) {
    return roster.last;
  }

  final safeIndex = index < 0 ? 0 : index;
  return roster[safeIndex];
}

String bestNameMatchFromRoster(List<String> roster, String detectedName) {
  if (roster.isEmpty) {
    return 'Student';
  }

  final normalizedDetected = detectedName.trim();
  if (normalizedDetected.isEmpty) {
    return roster.first;
  }

  final normalizedTarget = normalizedDetected.toLowerCase();

  for (final candidate in roster) {
    final normalizedCandidate = candidate.toLowerCase();
    if (normalizedCandidate == normalizedTarget ||
        normalizedCandidate.contains(normalizedTarget) ||
        normalizedTarget.contains(normalizedCandidate)) {
      return candidate;
    }
  }

  final sortedRoster = List<String>.from(roster)
    ..sort((a, b) => _nameSimilarity(b, normalizedTarget).compareTo(_nameSimilarity(a, normalizedTarget)));

  return sortedRoster.first;
}

int _nameSimilarity(String candidate, String target) {
  final candidateWords = candidate.toLowerCase().split(RegExp(r'\s+'));
  final targetWords = target.toLowerCase().split(RegExp(r'\s+'));
  int matches = 0;

  for (final targetWord in targetWords) {
    for (final candidateWord in candidateWords) {
      if (candidateWord == targetWord) {
        matches++;
      }
    }
  }

  return matches;
}

String _escapeCsvField(String value) {
  final escaped = value.replaceAll('"', '""');
  if (escaped.contains(',') || escaped.contains('"') || escaped.contains('\n')) {
    return '"$escaped"';
  }
  return escaped;
}

List<String> buildDefaultAnswerKey(int questionCount, {String defaultValue = 'A'}) {
  if (questionCount <= 0) {
    return const [];
  }

  const sampleKey = ['A', 'B', 'C', 'D', 'A'];
  return List<String>.generate(questionCount, (index) {
    if (index < sampleKey.length) {
      return sampleKey[index];
    }
    return defaultValue;
  });
}

List<String> extractStudentAnswersFromText(String scannedText, int questionCount) {
  if (questionCount <= 0) {
    return const [];
  }

  final letters = RegExp(r'(?<![A-Z])([A-D])(?![A-Z])')
      .allMatches(scannedText.toUpperCase())
      .map((match) => match.group(1) ?? '')
      .where((value) => value.isNotEmpty)
      .toList();

  if (letters.isEmpty) {
    return List<String>.filled(questionCount, 'A');
  }

  final normalized = letters.take(questionCount).toList();
  if (normalized.length < questionCount) {
    final padded = List<String>.from(normalized);
    while (padded.length < questionCount) {
      padded.add('A');
    }
    return padded;
  }

  return normalized;
}

class ExamTemplate {
  final String templateName;
  final String className;
  final String subjectName;
  final List<String> answerKey;

  ExamTemplate({
    required this.templateName,
    required this.className,
    required this.subjectName,
    required this.answerKey,
  });
}

class StudentResult {
  final String studentName;
  final String className;
  final String subjectName;
  final String templateName;
  final int score;
  final String remarks;
  final double confidence;
  final String scannedAt;

  StudentResult({
    required this.studentName,
    required this.className,
    required this.subjectName,
    this.templateName = '',
    required this.score,
    required this.remarks,
    this.confidence = 0.9,
    required this.scannedAt,
  });
}

class ScannerHomePage extends StatefulWidget {
  const ScannerHomePage({super.key});

  @override
  State<ScannerHomePage> createState() => _ScannerHomePageState();
}

class _ScannerHomePageState extends State<ScannerHomePage> {
  int _questionCount = 10;

  bool _isProcessing = false;
  int _currentScore = 0;
  final List<StudentResult> _studentRecords = [];
  final ImagePicker _picker = ImagePicker();
  late List<TextEditingController> _answerKeyControllers;
  late List<TextEditingController> _studentAnswerControllers;
  final TextEditingController _studentNameController = TextEditingController(text: 'Maria Santos');
  final TextEditingController _classNameController = TextEditingController(text: 'Grade 10 - Science');
  final TextEditingController _subjectNameController = TextEditingController(text: 'Science');
  final TextEditingController _templateNameController = TextEditingController(text: 'Science Midterm 1');
  final TextEditingController _rosterController = TextEditingController(
    text: 'Alice Santos\nBob Cruz\nMaria Santos\nRico Dela Cruz\nJanelle Lee',
  );
  int _rosterIndex = 0;
  final List<ExamTemplate> _savedTemplates = [
    ExamTemplate(
      templateName: 'Science Midterm 1',
      className: 'Grade 10 - Science',
      subjectName: 'Science',
      answerKey: ['A', 'B', 'C', 'D', 'A'],
    ),
  ];
  int _selectedTemplateIndex = 0;
  XFile? _capturedImage;
  String _lastScanName = '';

  @override
  void initState() {
    super.initState();
    _answerKeyControllers = List.generate(
      _questionCount,
      (index) => TextEditingController(text: buildDefaultAnswerKey(_questionCount)[index]),
    );
    _studentAnswerControllers = List.generate(
      _questionCount,
      (index) => TextEditingController(text: buildDefaultAnswerKey(_questionCount)[index]),
    );
  }

  List<String> _getAnswerKey() => _answerKeyControllers.map((controller) => controller.text).toList();

  List<String> _getStudentAnswers() => _studentAnswerControllers.map((controller) => controller.text).toList();

  void _setQuestionCount(int value) {
    final safeCount = value.clamp(1, 200);

    final newAnswerControllers = List.generate(
      safeCount,
      (index) {
        if (index < _answerKeyControllers.length) {
          return _answerKeyControllers[index];
        }
        return TextEditingController(text: buildDefaultAnswerKey(safeCount)[index]);
      },
    );

    final newStudentControllers = List.generate(
      safeCount,
      (index) {
        if (index < _studentAnswerControllers.length) {
          return _studentAnswerControllers[index];
        }
        return TextEditingController(text: buildDefaultAnswerKey(safeCount)[index]);
      },
    );

    if (safeCount < _answerKeyControllers.length) {
      for (final controller in _answerKeyControllers.sublist(safeCount)) {
        controller.dispose();
      }
    }
    if (safeCount < _studentAnswerControllers.length) {
      for (final controller in _studentAnswerControllers.sublist(safeCount)) {
        controller.dispose();
      }
    }

    setState(() {
      _questionCount = safeCount;
      _answerKeyControllers = newAnswerControllers;
      _studentAnswerControllers = newStudentControllers;
    });
  }

  String _generateAutoScanName() {
    final now = DateTime.now();
    final year = now.year.toString();
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    final hour = now.hour.toString().padLeft(2, '0');
    final minute = now.minute.toString().padLeft(2, '0');
    final second = now.second.toString().padLeft(2, '0');

    return 'scan_${year}${month}${day}_${hour}${minute}${second}.jpg';
  }

  Future<List<String>> _autoScanStudentAnswersFromImage(XFile imageFile) async {
    try {
      final inputImage = InputImage.fromFilePath(imageFile.path);
      final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
      final recognizedText = await textRecognizer.processImage(inputImage);
      await textRecognizer.close();

      final parsedAnswers = extractStudentAnswersFromText(recognizedText.text, _questionCount);
      return parsedAnswers;
    } catch (_) {
      return List<String>.filled(_questionCount, 'A');
    }
  }

  Future<void> _takeScanPicture() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.rear,
        imageQuality: 85,
      );

      if (image == null) {
        return;
      }

      final directory = await getApplicationDocumentsDirectory();
      final savedName = _generateAutoScanName();
      final savedPath = '${directory.path}/$savedName';
      final savedFile = await File(image.path).copy(savedPath);

      if (!mounted) {
        return;
      }

      final extractedAnswers = await _autoScanStudentAnswersFromImage(XFile(savedFile.path));

      setState(() {
        _capturedImage = XFile(savedFile.path);
        _lastScanName = savedName;
        for (int i = 0; i < _studentAnswerControllers.length; i++) {
          _studentAnswerControllers[i].text = i < extractedAnswers.length ? extractedAnswers[i] : 'A';
        }
      });

      final answerMessage = extractedAnswers.isEmpty || extractedAnswers.every((value) => value == 'A')
          ? 'Captured scan saved as: $savedName. OCR could not detect enough answer bubbles, so manual review is recommended.'
          : 'Captured scan saved as: $savedName and student answers were auto-filled from the sheet.';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(answerMessage)),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Camera error: $error')),
      );
    }
  }

  void _saveCurrentTemplate() {
    final templateName = _templateNameController.text.trim();
    final className = _classNameController.text.trim();
    final subjectName = _subjectNameController.text.trim();
    final answerKey = _getAnswerKey();

    if (templateName.isEmpty || className.isEmpty || subjectName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in the template name, class, and subject.')),
      );
      return;
    }

    final template = ExamTemplate(
      templateName: templateName,
      className: className,
      subjectName: subjectName,
      answerKey: answerKey,
    );

    setState(() {
      _savedTemplates.add(template);
      _selectedTemplateIndex = _savedTemplates.length - 1;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Saved template: $templateName')),
    );
  }

  void _loadTemplate(int index) {
    final template = _savedTemplates[index];
    final requiredQuestionCount = template.answerKey.length.clamp(1, 200);

    if (requiredQuestionCount != _questionCount) {
      _setQuestionCount(requiredQuestionCount);
    }

    setState(() {
      _selectedTemplateIndex = index;
      _templateNameController.text = template.templateName;
      _classNameController.text = template.className;
      _subjectNameController.text = template.subjectName;
      for (int i = 0; i < _answerKeyControllers.length; i++) {
        _answerKeyControllers[i].text = i < template.answerKey.length ? template.answerKey[i] : 'A';
      }
      for (int i = 0; i < _studentAnswerControllers.length; i++) {
        _studentAnswerControllers[i].text = i < template.answerKey.length ? template.answerKey[i] : 'A';
      }
    });
  }

  void _applyNextStudentFromRoster() {
    final roster = parseStudentRoster(_rosterController.text);
    if (roster.isEmpty) {
      return;
    }

    final nextStudent = nextStudentFromRoster(roster, _rosterIndex);
    _rosterIndex += 1;
    _studentNameController.text = nextStudent;
    _studentNameController.selection = TextSelection.fromPosition(
      TextPosition(offset: _studentNameController.text.length),
    );
  }

  void _gradeSheet() async {
    setState(() {
      _isProcessing = true;
    });

    await Future.delayed(const Duration(seconds: 2));

    final answerKey = _getAnswerKey();
    final studentAnswers = _getStudentAnswers();
    final correctAnswers = calculateScoreFromKey(answerKey, studentAnswers);
    final totalQuestions = answerKey.length;
    final percentage = totalQuestions == 0 ? 0 : ((correctAnswers / totalQuestions) * 100).round();

    String studentName = _studentNameController.text.trim();
    final roster = parseStudentRoster(_rosterController.text);
    if (studentName.isEmpty && roster.isNotEmpty) {
      studentName = nextStudentFromRoster(roster, _rosterIndex);
      _rosterIndex += 1;
      _studentNameController.text = studentName;
    } else if (roster.isNotEmpty && _studentNameController.text.trim().isEmpty) {
      studentName = nextStudentFromRoster(roster, _rosterIndex);
      _rosterIndex += 1;
    }

    if (studentName.isEmpty) {
      studentName = 'Student ${_studentRecords.length + 1}';
    }

    final className = _classNameController.text.trim().isEmpty ? 'Grade 10' : _classNameController.text.trim();
    final subjectName = _subjectNameController.text.trim().isEmpty ? 'General' : _subjectNameController.text.trim();
    final remarks = buildResultRemark(correctAnswers, totalQuestions);
    final confidence = totalQuestions == 0 ? 0.0 : (correctAnswers / totalQuestions).clamp(0.0, 1.0);
    final scannedAt = DateTime.now().toString().replaceFirst('T', ' ').substring(0, 16);

    setState(() {
      _isProcessing = false;
      _currentScore = percentage;
      _studentRecords.add(StudentResult(
        studentName: studentName,
        className: className,
        subjectName: subjectName,
        templateName: _templateNameController.text.trim().isEmpty ? 'Default Template' : _templateNameController.text.trim(),
        score: percentage,
        remarks: remarks,
        confidence: confidence,
        scannedAt: scannedAt,
      ));
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Successfully scanned and graded: $studentName ($correctAnswers/$totalQuestions correct)')),
    );
  }

  Future<void> _exportToExcel() async {
    if (_studentRecords.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('There are no scanned records to export yet.')),
      );
      return;
    }

    try {
      final workbook = buildGradebookWorkbook(_studentRecords);
      final fileBytes = workbook.encode();
      if (fileBytes == null) {
        throw Exception('Excel file encoding returned null.');
      }

      final directory = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final file = File('${directory.path}/gradebook_$timestamp.xlsx');
      await file.writeAsBytes(fileBytes);

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Exported ${_studentRecords.length} records to ${file.path}')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Excel export failed: $error')),
      );
    }
  }

  Widget _buildBrandLogo() {
    return Container(
      width: 84,
      height: 84,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.16),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withOpacity(0.25)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Image.asset(
          'assets/logo.png',
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          errorBuilder: (context, error, stackTrace) {
            return Image.asset(
              'assets/images.png',
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
              errorBuilder: (context, error, stackTrace) {
                return Image.asset(
                  'assets/teacher_photo.jpg',
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      width: 84,
                      height: 84,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(Icons.school_rounded, color: Colors.white, size: 38),
                    );
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.9),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAnswerKeyEditor() {
    return Container(
      padding: const EdgeInsets.all(18),
      margin: const EdgeInsets.only(bottom: 24),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.96),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.quiz_rounded, color: Colors.indigo),
              SizedBox(width: 8),
              Text(
                'Teacher Answer Key',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.indigo.shade50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'Questions: $_questionCount',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Colors.indigo,
                  ),
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () => _setQuestionCount(_questionCount + 5),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add 5'),
              ),
              if (_questionCount > 5)
                TextButton.icon(
                  onPressed: () => _setQuestionCount(_questionCount - 5),
                  icon: const Icon(Icons.remove_rounded),
                  label: const Text('Remove 5'),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: List.generate(_questionCount, (index) {
              return SizedBox(
                width: 120,
                child: TextField(
                  controller: _answerKeyControllers[index],
                  textAlign: TextAlign.center,
                  textCapitalization: TextCapitalization.characters,
                  maxLength: 1,
                  decoration: InputDecoration(
                    counterText: '',
                    labelText: 'Q${index + 1}',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.indigo),
                    ),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 18),
          const Text(
            'Sample student answers from the scanned sheet:',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: List.generate(_questionCount, (index) {
              return SizedBox(
                width: 120,
                child: TextField(
                  controller: _studentAnswerControllers[index],
                  textAlign: TextAlign.center,
                  textCapitalization: TextCapitalization.characters,
                  maxLength: 1,
                  decoration: InputDecoration(
                    counterText: '',
                    labelText: 'Q${index + 1}',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.green),
                    ),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final totalScanned = _studentRecords.length;
    final averageScore = totalScanned == 0
        ? 0
        : (_studentRecords.fold<int>(0, (sum, record) => sum + record.score) / totalScanned).round();
    final passCount = _studentRecords.where((record) => record.remarks == 'Passed').length;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Automated Answer Sheet Scanner & Gradebook'),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/background.jpg',
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return Image.asset(
                  'assets/images.png',
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Image.asset(
                      'assets/teacher_photo.jpg',
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return const SizedBox();
                      },
                    );
                  },
                );
              },
            ),
          ),
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.18),
              ),
            ),
          ),
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF1E3A8A), Color(0xFF3B82F6), Color(0xFF93C5FD)],
              ),
            ),
            child: SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth >= 900;

                  final content = isWide
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: _buildScannerPanel()),
                            const SizedBox(width: 20),
                            Expanded(child: _buildGradebookPanel()),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildScannerPanel(),
                            const SizedBox(height: 20),
                            _buildGradebookPanel(),
                          ],
                        );

                  return SingleChildScrollView(
                    padding: const EdgeInsets.all(24.0),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: constraints.maxHeight),
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(color: Colors.white.withOpacity(0.2)),
                            ),
                            child: Row(
                              children: [
                                _buildBrandLogo(),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: const [
                                      Text(
                                        'Smart Exam Scanner',
                                        style: TextStyle(
                                          fontSize: 28,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                      SizedBox(height: 8),
                                      Text(
                                        'Auto-capture, grade, and export answer sheets',
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: Colors.white70,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: const Icon(
                                    Icons.qr_code_scanner_rounded,
                                    size: 36,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                          Wrap(
                            spacing: 16,
                            runSpacing: 16,
                            children: [
                              SizedBox(
                                width: 180,
                                child: _buildStatCard(
                                  'Scans',
                                  totalScanned.toString(),
                                  Icons.camera_alt_rounded,
                                  Colors.blue,
                                ),
                              ),
                              SizedBox(
                                width: 180,
                                child: _buildStatCard(
                                  'Avg',
                                  '$averageScore%',
                                  Icons.bar_chart_rounded,
                                  Colors.green,
                                ),
                              ),
                              SizedBox(
                                width: 180,
                                child: _buildStatCard(
                                  'Pass',
                                  passCount.toString(),
                                  Icons.check_circle_rounded,
                                  Colors.orange,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                          _buildTemplateToolbar(),
                          _buildAnswerKeyEditor(),
                          content,
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    for (final controller in _answerKeyControllers) {
      controller.dispose();
    }
    for (final controller in _studentAnswerControllers) {
      controller.dispose();
    }
    _studentNameController.dispose();
    _classNameController.dispose();
    _subjectNameController.dispose();
    _templateNameController.dispose();
    _rosterController.dispose();
    super.dispose();
  }

  Widget _buildTemplateToolbar() {
    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.96),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Exam Template Manager',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _templateNameController,
                  decoration: InputDecoration(
                    labelText: 'Template Name',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: _saveCurrentTemplate,
                icon: const Icon(Icons.save_rounded),
                label: const Text('Save'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_savedTemplates.isNotEmpty)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: List.generate(_savedTemplates.length, (index) {
                final template = _savedTemplates[index];
                final isSelected = index == _selectedTemplateIndex;
                return ChoiceChip(
                  label: Text(template.templateName),
                  selected: isSelected,
                  onSelected: (_) => _loadTemplate(index),
                );
              }),
            ),
          const SizedBox(height: 12),
          TextField(
            controller: _rosterController,
            minLines: 3,
            maxLines: 5,
            decoration: InputDecoration(
              labelText: 'Class roster (one name per line)',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              helperText: 'Names will be auto-filled in order to speed up bulk scanning.',
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: ElevatedButton.icon(
              onPressed: _applyNextStudentFromRoster,
              icon: const Icon(Icons.skip_next_rounded),
              label: const Text('Auto-fill next student'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScannerPanel() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.94),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: const [
              Icon(Icons.document_scanner, color: Colors.indigo),
              SizedBox(width: 8),
              Text(
                'Scanner Panel',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _studentNameController,
                  decoration: InputDecoration(
                    labelText: 'Student Name',
                    prefixIcon: const Icon(Icons.person),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _classNameController,
                  decoration: InputDecoration(
                    labelText: 'Class / Section',
                    prefixIcon: const Icon(Icons.class_rounded),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _subjectNameController,
                  decoration: InputDecoration(
                    labelText: 'Subject',
                    prefixIcon: const Icon(Icons.subject_rounded),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            height: 320,
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.blue.shade100),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: _isProcessing
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 12),
                          Text('Processing answer sheet...'),
                        ],
                      ),
                    )
                  : _capturedImage != null
                      ? Image.file(
                          File(_capturedImage!.path),
                          fit: BoxFit.cover,
                        )
                      : const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.camera_alt_outlined, size: 64, color: Colors.blueGrey),
                              SizedBox(height: 12),
                              Text('Ready to auto-scan answer sheet'),
                            ],
                          ),
                        ),
            ),
          ),
          const SizedBox(height: 16),
          if (_lastScanName.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.indigo.shade50,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Last scan: $_lastScanName',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Colors.indigo,
                ),
              ),
            ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _isProcessing ? null : _takeScanPicture,
            icon: const Icon(Icons.camera_alt),
            label: const Text('Take Scan Photo'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              backgroundColor: Colors.indigo,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: _isProcessing ? null : _gradeSheet,
            icon: const Icon(Icons.auto_awesome),
            label: const Text('Scan & Grade Sheet Automatically'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              backgroundColor: Colors.green.shade600,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGradebookPanel() {
    final reviewQueue = _studentRecords.where((record) => record.confidence < 0.8).toList();

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.94),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: const [
              Icon(Icons.table_chart_rounded, color: Colors.green),
              SizedBox(width: 8),
              Text(
                'Scanned Class Gradebook',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (_studentRecords.isEmpty)
            const SizedBox(
              height: 240,
              child: Center(
                child: Text(
                  'No sheets scanned yet.',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            )
          else
            SizedBox(
              height: 320,
              child: ListView.separated(
                itemCount: _studentRecords.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final record = _studentRecords[index];
                  final isPassed = record.remarks == 'Passed';
                  final reviewState = buildReviewDecision(record.confidence);

                  return Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 22,
                          backgroundColor: isPassed ? Colors.green.shade100 : Colors.orange.shade100,
                          child: Icon(
                            isPassed ? Icons.check : Icons.close,
                            color: isPassed ? Colors.green : Colors.orange,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                record.studentName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${record.className} • ${record.subjectName}',
                                style: const TextStyle(
                                  color: Colors.grey,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Remarks: ${record.remarks} • ${reviewState} • ${record.scannedAt}',
                                style: TextStyle(
                                  color: isPassed ? Colors.green.shade700 : Colors.orange.shade700,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: isPassed ? Colors.green.shade100 : Colors.orange.shade100,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${record.score}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: isPassed ? Colors.green.shade800 : Colors.orange.shade800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.amber.shade50,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.warning_amber_rounded, color: Colors.amber),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Review queue: ${reviewQueue.length} item${reviewQueue.length == 1 ? '' : 's'}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: _studentRecords.isEmpty ? null : _exportToExcel,
            icon: const Icon(Icons.table_chart),
            label: Text('Export All (${_studentRecords.length}) to Excel'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green.shade700,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}