// Word（.docx）题目解析。
//
// 思路复用刷题 App 的 DocumentImporter.docxText：.docx 本质是 zip 包，
// 解开后读 word/document.xml，剥掉 XML 标签即正文，再调 parseFormattedText。
// 老版 .doc 是二进制格式、不是 zip，解不开，直接抛错提示另存为 .docx。

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../../models/models.dart';
import 'question_parser.dart' show parseFormattedText;

/// 从 .docx 字节提纯文本（段落变回车，剥标签，还原 XML 转义符）。
String docxText(Uint8List bytes) {
  Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(bytes);
  } catch (_) {
    throw const FormatException('这个 Word 文件解不开；如果是老版 .doc，请在 Word/WPS 里另存为 .docx 后再导入');
  }
  final entry = archive.findFile('word/document.xml');
  if (entry == null) {
    throw const FormatException('这个 Word 文件里找不到正文；如果是老版 .doc，请在 Word/WPS 里另存为 .docx 后再导入');
  }
  final xml = utf8.decode(entry.content as List<int>);
  var text = xml
      .replaceAll('</w:p>', '\n')
      .replaceAll(RegExp(r'<w:tab[^>]*/>'), '\t')
      .replaceAll(RegExp(r'<w:br[^>]*/>'), '\n')
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&amp;', '&');
  text = text.trim();
  if (text.length < 10) {
    throw const FormatException('这个 Word 文件里没读到多少文字，检查一下文件是不是空的');
  }
  return text;
}

/// 从 .docx 字节解析题目。`.doc`（老版二进制）直接抛错，提示另存为 .docx。
List<Question> parseDocxBytes(Uint8List bytes) {
  return parseFormattedText(docxText(bytes));
}

/// 按文件名后缀校验：`.doc` 直接抛错，不尝试解析。
void checkWordExtension(String path) {
  final lower = path.toLowerCase();
  if (lower.endsWith('.doc') && !lower.endsWith('.docx')) {
    throw const FormatException('老版 .doc 导不了，请在 Word/WPS 里另存为 .docx 后再导入');
  }
}
