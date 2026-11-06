// 导入总入口：按文件扩展名分发到各解析器。
//
// 签名按 CONTRACT.md，不得改名：
//   Future<List<Question>> parseFile(String path)
// 支持：.xlsx / .xls → Excel；.docx → Word；.pdf → Edge Function 提取；
//       .txt → 文字版解析；.csv → CSV；.json → JSON。
// 不支持：.doc（老版 Word，提示另存为 .docx）；扫描版 PDF（无文字层）。
// 导入 0 题时抛错“没有解析到题目”。

import 'dart:convert';
import 'dart:io';

import '../models/models.dart';
import 'parsers/excel_parser.dart' show parseExcelBytes;
import 'parsers/pdf_text_parser.dart' show parsePdfBytes;
import 'parsers/question_parser.dart'
    show parseCsv, parseFormattedText, parseJson;
import 'parsers/word_parser.dart' show checkWordExtension, parseDocxBytes;

class ImportService {
  /// PDF 提取 Edge Function 地址与 anon key（占位，真实值来自 app_config）。
  ///
  /// 不传时 PDF 导入会在配置检查处抛中文错；其他格式不受影响。
  final String pdfExtractUrl;
  final String anonKey;

  const ImportService({this.pdfExtractUrl = '', this.anonKey = ''});

  /// 按扩展名分发解析。未知扩展名抛错；0 题抛错“没有解析到题目”。
  Future<List<Question>> parseFile(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      throw FormatException('找不到文件：$path');
    }
    final lower = path.toLowerCase();
    final bytes = await file.readAsBytes();

    late final List<Question> questions;
    if (lower.endsWith('.xlsx') || lower.endsWith('.xls')) {
      questions = parseExcelBytes(bytes);
    } else if (lower.endsWith('.docx')) {
      questions = parseDocxBytes(bytes);
    } else if (lower.endsWith('.doc')) {
      checkWordExtension(path); // 内部抛错：请另存为 .docx
      questions = const []; // 走不到这里；写出来只是为了让类型检查通过。
    } else if (lower.endsWith('.pdf')) {
      questions = await parsePdfBytes(
        bytes,
        edgeFunctionUrl: pdfExtractUrl,
        anonKey: anonKey,
      );
    } else if (lower.endsWith('.txt')) {
      questions = parseFormattedText(_readText(bytes));
    } else if (lower.endsWith('.csv')) {
      questions = parseCsv(_readText(bytes));
    } else if (lower.endsWith('.json')) {
      questions = parseJson(_readText(bytes));
    } else {
      throw FormatException('不支持的文件格式：${_extensionOf(path)}，支持 xlsx、docx、pdf、txt、csv、json');
    }

    if (questions.isEmpty) {
      throw const FormatException('没有解析到题目');
    }
    return questions;
  }

  /// 文本文件解码：先 UTF-8，失败再用 latin1 兜底（不丢字节；GBK 编码的 CSV
  /// 仍可能乱码，见 docs/IMPORT_TEMPLATES.md，建议另存为 UTF-8）。
  String _readText(List<int> bytes) {
    try {
      return const Utf8Decoder().convert(bytes);
    } catch (_) {
      return latin1.decode(bytes);
    }
  }

  String _extensionOf(String path) {
    final dot = path.lastIndexOf('.');
    if (dot < 0) return '（无扩展名）';
    return path.substring(dot);
  }
}
