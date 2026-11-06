// PDF 文字提取。
//
// 限制（先说清楚）：Flutter 端没有可靠的 PDF 文字提取库，做不了 PDF 解析。
// 因此分两步走：
//   1) 本地快速检测：用 archive 包尝试解压 PDF 流里的文字（见 hasExtractableText）。
//      提不到文字就直接抛错“这是扫描版 PDF，没有文字层，请转文字版 PDF 再导入”，
//      不发网络请求、不让用户白等。
//   2) 真正提取走 Supabase Edge Function pdf-extract
//     （supabase/functions/pdf-extract/index.ts，Deno + pdfjs），
//      提取出的文本再调 parseFormattedText 解析成题。
// 扫描版 PDF（全是图片、无文字层）导不了，这是 P0 的硬限制，见 CONTRACT.md。

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;

import '../../models/models.dart';
import 'question_parser.dart' show parseFormattedText;

/// PDF 流里 Tj / TJ 算子后括号字符串的粗略提取：
///
/// 只做“有没有文字”的快速判断，不做精确排版还原。
/// 做法：找 `stream ... endstream` 段，尝试 zlib 解压（/FlateDecode 的流），
//  解压出的内容里找 `(...)Tj` / `[...]TJ`，数括号里的可打印字符。
String _extractLooseText(Uint8List bytes) {
  final raw = latin1.decode(bytes, allowInvalid: true);
  final buffer = StringBuffer();
  final streamRe = RegExp(r'stream\r?\n(.*?)endstream', dotAll: true);
  for (final m in streamRe.allMatches(raw)) {
    final chunk = m.group(1)!;
    List<int>? decompressed;
    try {
      decompressed = ZLibDecoder().decodeBytes(
        latin1.encode(chunk),
      );
    } catch (_) {
      // 非 Flate 流或解压失败：直接在原文里找括号字符串。
      decompressed = null;
    }
    final text = decompressed == null
        ? chunk
        : latin1.decode(decompressed, allowInvalid: true);
    final tjRe = RegExp(r'\((?:[^()\\]|\\.)*\)\s*(?:Tj|TJ|Tj)');
    for (final t in tjRe.allMatches(text)) {
      var s = t.group(0)!;
      s = s.replaceAll(RegExp(r'\)\s*(?:Tj|TJ)$'), '');
      s = s.substring(1); // 去掉开头的 (
      s = s.replaceAll(r'\(', '(').replaceAll(r'\)', ')');
      buffer.write(s);
      buffer.write(' ');
    }
  }
  return buffer.toString();
}

/// 本地快速检测：PDF 里是否提得到文字层。
///
/// 返回 true = 疑似有文字层，可以继续调 Edge Function 精确提取；
/// 返回 false = 几乎肯定是扫描版（无文字层），调用方应直接抛错，不发请求。
bool hasExtractableText(Uint8List bytes) {
  if (bytes.length < 5) return false;
  final header = ascii.decode(bytes.sublist(0, 5), allowInvalid: true);
  if (!header.startsWith('%PDF')) return false;
  final loose = _extractLooseText(bytes);
  // 阈值：能抠出 20 个以上可读字符才算有文字层（与刷题 App 的 20 字口径一致）。
  final readable = loose.replaceAll(RegExp(r'\s'), '');
  return readable.length >= 20;
}

/// 调 Supabase Edge Function pdf-extract，把 PDF 文本取回来。
///
/// [edgeFunctionUrl] 如 `https://<项目>.supabase.co/functions/v1/pdf-extract`
/// （占位格式，真实地址填在 lib/app_config.dart，绝不写进代码）；
/// [anonKey] 为 Supabase anon key，同样来自 app_config。
/// 失败时抛中文错；扫描版（服务端也提不到文字）会返回 422，文案见服务端。
Future<String> extractTextViaEdgeFunction(
  Uint8List bytes, {
  required String edgeFunctionUrl,
  required String anonKey,
}) async {
  if (edgeFunctionUrl.isEmpty || anonKey.isEmpty) {
    throw const FormatException('PDF 提取服务还没配置，请先在 lib/app_config.dart 填入 Supabase 地址和 Key');
  }
  late final http.Response resp;
  try {
    resp = await http
        .post(
          Uri.parse(edgeFunctionUrl),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $anonKey',
            'apikey': anonKey,
          },
          body: jsonEncode({'pdfBase64': base64Encode(bytes)}),
        )
        .timeout(const Duration(seconds: 60));
  } catch (_) {
    throw const FormatException('PDF 提取服务连不上，请检查网络后重试');
  }
  if (resp.statusCode == 422) {
    throw const FormatException('这是扫描版 PDF，没有文字层，请转文字版 PDF 再导入');
  }
  if (resp.statusCode != 200) {
    throw FormatException('PDF 提取失败（${resp.statusCode}），请稍后重试');
  }
  dynamic decoded;
  try {
    decoded = jsonDecode(resp.body);
  } catch (_) {
    throw const FormatException('PDF 提取服务返回了看不懂的内容，请稍后重试');
  }
  final text = (decoded is Map ? decoded['text']?.toString() ?? '' : '').trim();
  if (text.length < 10) {
    throw const FormatException('这是扫描版 PDF，没有文字层，请转文字版 PDF 再导入');
  }
  return text;
}

/// 从 PDF 字节解析题目：先本地快速检测，再走 Edge Function 提取，最后解析。
///
/// [edgeFunctionUrl] / [anonKey] 为空时，本地检测通过也无法继续，会抛配置错。
Future<List<Question>> parsePdfBytes(
  Uint8List bytes, {
  String edgeFunctionUrl = '',
  String anonKey = '',
}) async {
  if (!hasExtractableText(bytes)) {
    throw const FormatException('这是扫描版 PDF，没有文字层，请转文字版 PDF 再导入');
  }
  final text = await extractTextViaEdgeFunction(
    bytes,
    edgeFunctionUrl: edgeFunctionUrl,
    anonKey: anonKey,
  );
  return parseFormattedText(text);
}
