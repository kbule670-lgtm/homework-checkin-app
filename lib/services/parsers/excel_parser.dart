// Excel（.xlsx / .xls）题目解析。
//
// 依赖：pubspec.yaml 需加 excel 包（A 组负责 pubspec.yaml，见 CONTRACT.md）。
// 只读第一张表，首行是表头；列定义见 docs/IMPORT_TEMPLATES.md。

import 'dart:typed_data';

import 'package:excel/excel.dart';

import '../../models/models.dart';
import 'question_parser.dart' show parseCsv;

/// 从 Excel 字节解析题目。
///
/// 表头（首行，列名按以下别名识别）：
/// 题干 | 类型(choice/fill) | 选项A | 选项B | 选项C | 选项D | 选项E(可选) | 答案 | 分值
/// - 跳过空行；类型缺省时有选项算 choice、无选项算 fill。
/// - 返回的 Question 的 id 先置空字符串，入库时由数据库生成。
List<Question> parseExcelBytes(Uint8List bytes) {
  final excel = Excel.decodeBytes(bytes);
  if (excel.tables.isEmpty) {
    throw const FormatException('Excel 里没有工作表');
  }
  final sheet = excel.tables.values.first;
  final rows = sheet.rows;
  if (rows.length < 2) {
    throw const FormatException('Excel 里没有题目行（首行是表头，从第二行起是题目）');
  }

  String cell(List<Data?> row, int index) {
    if (index < 0 || index >= row.length) return '';
    final value = row[index]?.value;
    if (value == null) return '';
    return value.toString().trim();
  }

  int headerIndex(List<String> header, List<String> names) {
    for (var i = 0; i < header.length; i++) {
      if (names.contains(header[i].trim())) return i;
    }
    return -1;
  }

  final header = rows.first.map((c) => c?.value?.toString() ?? '').toList();
  final stemIdx = headerIndex(header, ['题干', 'stem']);
  final typeIdx = headerIndex(header, ['类型', 'type']);
  final answerIdx = headerIndex(header, ['答案', 'answer']);
  final pointsIdx = headerIndex(header, ['分值', 'points', '分数']);
  final optionIdx = [
    headerIndex(header, ['选项A', 'A']),
    headerIndex(header, ['选项B', 'B']),
    headerIndex(header, ['选项C', 'C']),
    headerIndex(header, ['选项D', 'D']),
    headerIndex(header, ['选项E', 'E']),
  ];
  if (stemIdx < 0) {
    throw const FormatException('Excel 表头里找不到“题干”列');
  }

  final questions = <Question>[];
  for (var i = 1; i < rows.length; i++) {
    final row = rows[i];
    if (row.every((c) => (c?.value?.toString() ?? '').trim().isEmpty)) {
      continue; // 跳过空行
    }
    final stem = cell(row, stemIdx);
    if (stem.isEmpty) continue;
    final options = <String>[];
    for (final idx in optionIdx) {
      final v = cell(row, idx);
      if (v.isNotEmpty) options.add(v);
    }
    final rawType = cell(row, typeIdx).toLowerCase();
    final QuestionType type;
    if (rawType == 'fill' || rawType == '填空') {
      type = QuestionType.fill;
    } else if (rawType == 'choice' || rawType == '选择' || rawType == '单选') {
      type = QuestionType.choice;
    } else {
      type = options.isNotEmpty ? QuestionType.choice : QuestionType.fill;
    }
    final answer = cell(row, answerIdx);
    final points = int.tryParse(cell(row, pointsIdx)) ?? 5;
    questions.add(Question(
      id: '',
      assignmentId: '',
      type: type,
      stem: stem,
      options: type == QuestionType.choice ? options : const [],
      answer: answer,
      points: points,
      sortOrder: questions.length,
    ));
  }
  if (questions.isEmpty) {
    throw const FormatException('没有解析到题目，请检查 Excel 格式（见 docs/IMPORT_TEMPLATES.md）');
  }
  return questions;
}

/// 兼容入口：已有 CSV 文本时直接走 CSV 解析（便于单测与旧调用方）。
List<Question> parseExcelCsvText(String csvText) => parseCsv(csvText);
