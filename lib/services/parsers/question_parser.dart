// 文字版 / CSV / JSON 题目解析。
//
// 复用刷题 App 的解析思路（题号切块 → 选项标记 → 答案行），按本 App 的
// Question 模型（见 CONTRACT.md，lib/models/models.dart，A 组编写）重写。
// 注意：缺答案的题不丢弃，answer 置空字符串保留，由老师在发作业前补全。

import 'dart:convert';

import '../../models/models.dart';

/// 把全角标点/字母/数字归一化成半角（刷题 App 同款做法）。
String _normalize(String raw) {
var text = raw
.replaceAll('［', '[')
.replaceAll('］', ']')
.replaceAll('', ']')
.replaceAll('（', '(')
.replaceAll('）', ')')
.replaceAll('：', ':')
.replaceAll('，', ',')
.replaceAll('。', '.')
.replaceAll('　', ' ');
const fullLetters = ['Ａ', 'Ｂ', 'Ｃ', 'Ｄ', 'Ｅ'];
const halfLetters = ['A', 'B', 'C', 'D', 'E'];
for (var i = 0; i < fullLetters.length; i++) {
text = text.replaceAll(fullLetters[i], halfLetters[i]);
}
const fullDigits = ['０', '１', '２', '３', '４', '５', '６', '７', '８', '９'];
for (var i = 0; i < fullDigits.length; i++) {
text = text.replaceAll(fullDigits[i], '$i');
}
return text;
}

Question _build({
required QuestionType type,
required String stem,
required List<String> options,
required String answer,
required int points,
required int sortOrder,
}) {
// id 与 assignmentId 先置空，入库时由数据库生成 / 调用方填入。
return Question(
id: '',
assignmentId: '',
type: type,
stem: stem,
options: options,
answer: answer,
points: points,
sortOrder: sortOrder,
);
}

/// 题号标记：行首的 `1.` / `1、` / `1)` / `[1]` / `第1题`。
final _questionMark = RegExp(
r'^\s*(?:\[(\d{1,4})\]|(\d{1,4})[.、．)]|第\s*(\d{1,4})\s*题)\s*',
multiLine: true,
);

/// 答案行：`答案：B` / `答案 B` / `正确答案：B` / `答案：BC`（多选连写）。
final _answerLine = RegExp(
r'(?:答案|正确答案)\s*[:：]?\s*([A-E](?:\s*[,，、]?\s*[A-E])*)',
);

/// 填空题答案行：`答案：xxx`（xxx 不是 A-E 字母串时按填空答案处理）。
final _fillAnswerLine = RegExp(
r'(?:答案|正确答案)\s*[:：]?\s*([^\n]+)',
);

/// 题干末尾括号答案：`……（B）` / `……(B)`。
final _bracketAnswer = RegExp(r'[\(（]\s*([A-E])\s*[\)）]\s*$');

/// 选项标记：`A.` / `A、` / `A:` / `A `（后跟中文或内容）。
final _optionMark = RegExp(r'([A-E])[.、．:：]');

/// 解析文字版题目（txt / Word / PDF 文字层提取后的文本共用）。
///
/// 认的排版：
/// ```text
/// 1. 下列哪个是光合作用的场所？
/// A. 线粒体 B. 叶绿体 C. 细胞核 D. 高尔基体
/// 答案：B
///
/// 2. 请写出水的化学式：______
/// 答案：H2O
/// ```
/// - 选项可分行、可挤在一行；最多认到 E。
/// - 答案认「答案：B」「答案 B」「题干后（B）」三种写法；填空题答案为文字。
/// - 缺答案的题不丢弃，answer 为空字符串，调用方应在发作业前提醒老师补全。
List<Question> parseFormattedText(String text) {
final normalized = _normalize(text);
final marks = _questionMark.allMatches(normalized).toList();
if (marks.isEmpty) {
throw FormatException('没找到题号，请按“题号开头、一行一道题”的格式写（见 docs/IMPORT_TEMPLATES.md）');
}

final questions = <Question>[];
for (var i = 0; i < marks.length; i++) {
final start = marks[i].end;
final end = i + 1 < marks.length? marks[i + 1].start: normalized.length;
var block = normalized.substring(start, end).trim();
if (block.isEmpty) continue;

var answer = '';

// 1) 先抠答案行。字母答案优先；字母不匹配时按填空文字答案收。
final answerMatch = _answerLine.firstMatch(block);
if (answerMatch!= null) {
answer = answerMatch
.group(1)!
.replaceAll(RegExp(r'[\s,，、]'), '')
.toUpperCase();
block = block.replaceFirst(_answerLine, '').trim();
} else {
final fillMatch = _fillAnswerLine.firstMatch(block);
if (fillMatch!= null) {
final candidate = fillMatch.group(1)!.trim();
// 排除“答案：”后面跟的是解析等说明文字的极端情况：只收较短的答案。
if (candidate.isNotEmpty && candidate.length <= 40) {
answer = candidate;
block = block.replaceFirst(_fillAnswerLine, '').trim();
}
}
}

// 2) 没答案行时，认题干末尾的（B）。
if (answer.isEmpty) {
final bracket = _bracketAnswer.firstMatch(block);
if (bracket!= null) {
answer = bracket.group(1)!;
block = block.replaceFirst(_bracketAnswer, '').trim();
}
}

// 3) 抠选项：按 A. B. C. D. E. 标记切分，标记之间即选项内容。
final optionMatches = _optionMark.allMatches(block).toList();
final options = <String>[];
String stem;
if (optionMatches.length >= 2) {
stem = block.substring(0, optionMatches.first.start).trim();
for (var j = 0; j < optionMatches.length; j++) {
final s = optionMatches[j].end;
final e = j + 1 < optionMatches.length
? optionMatches[j + 1].start
: block.length;
final content = block.substring(s, e).trim();
if (content.isNotEmpty) options.add(content);
}
// 选项标记必须从 A 起连续，否则视为误切（题干里的 A 股之类），回退为填空。
const letters = ['A', 'B', 'C', 'D', 'E'];
var continuous = true;
for (var j = 0; j < options.length; j++) {
if (optionMatches[j].group(1)!= letters[j]) {
continuous = false;
break;
}
}
if (!continuous) {
options.clear();
stem = block;
}
} else {
stem = block;
}

// 题干里残留的换行折成空格；多余的“答案”残行已在上面剥掉。
stem = stem.replaceAll(RegExp(r'\s*\n\s*'), ' ').trim();
if (stem.isEmpty) continue;

final type = options.length >= 2
? QuestionType.choice
: QuestionType.fill;
// 填空题答案若是字母串（如答案 B）也按文字保留，不做校验。
questions.add(_build(
type: type,
stem: stem,
options: options,
answer: answer,
points: 5,
sortOrder: questions.length,
));
}

if (questions.isEmpty) {
throw FormatException('没有解析到题目，请检查文件格式（见 docs/IMPORT_TEMPLATES.md）');
}
return questions;
}

/// 最小可用 CSV 解析：认双引号包裹，逗号/换行在引号里不算分隔符。
List<List<String>> _parseCsvRows(String text) {
final rows = <List<String>>[];
var row = <String>[];
var field = StringBuffer();
var inQuotes = false;
final chars = text.runes.toList();
var i = 0;
while (i < chars.length) {
final c = String.fromCharCode(chars[i]);
if (inQuotes) {
if (c == '"') {
if (i + 1 < chars.length &&
String.fromCharCode(chars[i + 1]) == '"') {
field.write('"');
i++;
} else {
inQuotes = false;
}
} else {
field.write(c);
}
} else {
if (c == '"') {
inQuotes = true;
} else if (c == ',') {
row.add(field.toString());
field = StringBuffer();
} else if (c == '\n' || c == '\r') {
if (c == '\r' &&
i + 1 < chars.length &&
String.fromCharCode(chars[i + 1]) == '\n') {
i++;
}
row.add(field.toString());
field = StringBuffer();
rows.add(row);
row = <String>[];
} else {
field.write(c);
}
}
i++;
}
row.add(field.toString());
rows.add(row);
return rows;
}

int _headerIndex(List<String> header, List<String> names) {
for (var i = 0; i < header.length; i++) {
final h = header[i].trim();
if (names.contains(h)) return i;
}
return -1;
}

String _cell(List<String> row, int index) {
if (index < 0 || index >= row.length) return '';
return row[index].trim();
}

QuestionType _parseType(String raw, List<String> options) {
final t = raw.trim().toLowerCase();
if (t == 'fill' || t == '填空') return QuestionType.fill;
if (t == 'choice' || t == '选择' || t == '单选' || t == '选择题') {
return QuestionType.choice;
}
// 类型缺省：有选项算选择，无选项算填空。
return options.isNotEmpty? QuestionType.choice: QuestionType.fill;
}

/// 解析 CSV。
///
/// 列定义（首行为表头，列名可按下列别名写）：
/// 题干,类型(choice/fill),选项A,选项B,选项C,选项D,答案,分值
/// 类型列可空，缺省按有选项算 choice、无选项算 fill。
List<Question> parseCsv(String text) {
final rows = _parseCsvRows(text)
.where((r) => r.any((c) => c.trim().isNotEmpty))
.toList();
if (rows.length < 2) {
throw FormatException('CSV 里没有题目行（首行是表头，从第二行起是题目）');
}
final header = rows.first;
final stemIdx = _headerIndex(header, ['题干', 'stem']);
final typeIdx = _headerIndex(header, ['类型', 'type']);
final answerIdx = _headerIndex(header, ['答案', 'answer']);
final pointsIdx = _headerIndex(header, ['分值', 'points', '分数']);
final optionIdx = [
_headerIndex(header, ['选项A', 'A']),
_headerIndex(header, ['选项B', 'B']),
_headerIndex(header, ['选项C', 'C']),
_headerIndex(header, ['选项D', 'D']),
_headerIndex(header, ['选项E', 'E']),
];
if (stemIdx < 0) {
throw FormatException('CSV 表头里找不到“题干”列');
}

final questions = <Question>[];
for (var i = 1; i < rows.length; i++) {
final row = rows[i];
final stem = _cell(row, stemIdx);
if (stem.isEmpty) continue;
final options = <String>[];
for (final idx in optionIdx) {
final v = _cell(row, idx);
if (v.isNotEmpty) options.add(v);
}
final type = _parseType(_cell(row, typeIdx), options);
final answer = _cell(row, answerIdx);
final points = int.tryParse(_cell(row, pointsIdx))?? 5;
questions.add(_build(
type: type,
stem: stem,
options: type == QuestionType.choice? options: const [],
answer: answer,
points: points,
sortOrder: questions.length,
));
}
if (questions.isEmpty) {
throw FormatException('没有解析到题目，请检查 CSV 格式（见 docs/IMPORT_TEMPLATES.md）');
}
return questions;
}

/// 解析 JSON：顶层为数组，或 {"questions": [...]} 包一层。
///
/// 每项字段：stem（题干）、type（choice/fill，可空）、
/// options（选项数组，可空）、answer（答案，可空）、points（分值，可空，默认 5）。
List<Question> parseJson(String text) {
dynamic decoded;
try {
decoded = jsonDecode(text);
} catch (_) {
throw const FormatException('JSON 格式不对，请检查括号和引号');
}
List<dynamic> items;
if (decoded is List) {
items = decoded;
} else if (decoded is Map && decoded['questions'] is List) {
items = decoded['questions'] as List;
} else {
throw const FormatException('JSON 顶层应为题目数组，或 {"questions": [...]}');
}

final questions = <Question>[];
for (var i = 0; i < items.length; i++) {
final item = items[i];
if (item is! Map) {
throw FormatException('JSON 第 ${i + 1} 项不是对象');
}
final stem = (item['stem']?? '').toString().trim();
if (stem.isEmpty) continue;
final rawOptions = item['options'];
final options = <String>[];
if (rawOptions is List) {
for (final o in rawOptions) {
final v = o.toString().trim();
if (v.isNotEmpty) options.add(v);
}
}
final type = _parseType((item['type']?? '').toString(), options);
final answer = (item['answer']?? '').toString().trim();
final points = item['points'] is num
? (item['points'] as num).toInt()
: int.tryParse((item['points']?? '').toString())?? 5;
questions.add(_build(
type: type,
stem: stem,
options: type == QuestionType.choice? options: const [],
answer: answer,
points: points,
sortOrder: questions.length,
));
}
if (questions.isEmpty) {
throw FormatException('没有解析到题目，请检查 JSON 格式（见 docs/IMPORT_TEMPLATES.md）');
}
return questions;
}
