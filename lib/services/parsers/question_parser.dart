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
.replaceAll('【', '[')
.replaceAll('】', ']')
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

/// 题干末尾括号答案：`……（B）` / `……(B)`。行尾匹配（multiLine），因为
/// 选择题的题干后还跟着选项行，括号答案在行尾、不在整块末尾。
final _bracketAnswer =
    RegExp(r'[\(（]\s*([A-E])\s*[\)）]\s*$', multiLine: true);

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
/// - 一块里粘了两道题（多个答案行）时，启发式劈开：从第一个答案行之后
///   第一个非空行处劈成两道；劈不开就原样保留一道（纯规则，不用 AI）。
/// - 切题用记分制（候选 → 评分 → 阈值）：≥7 高置信切题，4–6 待确认
///   （照样切，标出来让老师检查），<4 不切；每切点的得分与明细挂在
///   Question.parseScore/parseReasons 上。
/// 切题器记分制（用户的记分制方案；刷题 App 切题器同款思路：候选 → 评分 → 阈值）。
///
/// 评分表：
/// - 题型标记（单选/多选/判断/填空/简答）+3
/// - 后续有标准选项结构（A、B 按序出现，或正确/错误成对）+3
/// - 题号连续（或从 1 重排、或首题不计连续）+2；题号递增 +1
/// - 前面 48 字内有上一题答案/解析结束标志 +3
/// - 题号后有完整题干（≥4 字）+2
/// - 格式不规范/OCR 歧义的弱标记（[n 缺右括号）-2
/// - 疑似年份/句中数字（行中出现且无题型标记，或 1900–2099 且无题型标记）-3
/// - 孤立题号（标记后没有题干）-3
/// - 行首点号题号弱佐证（没题型、没连续性、前面也没答案行时）-2
/// 判定：≥7 高置信切题；4–6 待确认（照样切，标出来让老师检查）；
/// <4 不切。跳号/重复号不以连续性为必要条件；跨页不自动切
/// （没有标记就不会切）；没选项的题也能切（不强制要求 A–D）。
/// 每个切点的得分与明细挂在 Question.parseScore/parseReasons 上。
class _Candidate {
  final int start;
  final int markerEnd;
  final int number;
  final String? hint;
  final bool atLineStart;
  final bool weakForm;
  final bool isDotted;
  int score = 0;
  final List<String> reasons = <String>[];
  bool pending = false;

  _Candidate({
    required this.start,
    required this.markerEnd,
    required this.number,
    required this.hint,
    required this.atLineStart,
    required this.weakForm,
    required this.isDotted,
  });
}

/// 候选标记正则（归一化后括号都是半角）。分组与下面 _findCandidates 一一对应：
/// 1,2=[n](型) 3,4=[n(型) 5=[n 6,7=(n)(型) 8=第n题 9,10=n(型) 11=行首n.
final _candidatePattern = RegExp(
  r'\[(\d{1,4})\][ \t]*(?:[\[(]?(单选|多选|判断|填空|简答)[\]\)])?'
  r'|\[(\d{1,4})[ \t]*[\[(](单选|多选|判断|填空|简答)[\]\)]?'
  r'|\[(\d{1,4})(?=[ \t])'
  r'|\((\d{1,4})\)[ \t]*(?:[\[(]?(单选|多选|判断|填空|简答)[\]\)])?'
  r'|第[ \t]*(\d{1,4})[ \t]*题'
  r'|(\d{1,4})[ \t]*[\[(](单选|多选|判断|填空|简答)[\]\)]'
  r'|^[ \t]*(\d{1,4})[ \t]*[.、．)]',
  multiLine: true,
);

/// 在归一化文本里找全部候选并按记分制打分（不含连续性分，连续性由
/// _selectBoundaries 按顺序补）。
List<_Candidate> _findCandidates(String normalized) {
  final matches = _candidatePattern.allMatches(normalized).toList();
  final candidates = <_Candidate>[];
  for (var i = 0; i < matches.length; i++) {
    final m = matches[i];
    String? numStr;
    String? hint;
    var weakForm = false;
    var isDotted = false;
    if (m.group(1) != null) {
      numStr = m.group(1);
      hint = m.group(2);
    } else if (m.group(3) != null) {
      numStr = m.group(3);
      hint = m.group(4);
      weakForm = true;
    } else if (m.group(5) != null) {
      numStr = m.group(5);
      weakForm = true;
    } else if (m.group(6) != null) {
      numStr = m.group(6);
      hint = m.group(7);
    } else if (m.group(8) != null) {
      numStr = m.group(8);
    } else if (m.group(9) != null) {
      numStr = m.group(9);
      hint = m.group(10);
    } else if (m.group(11) != null) {
      numStr = m.group(11);
      isDotted = true;
    } else {
      continue;
    }
    final number = int.tryParse(numStr ?? '');
    if (number == null || number < 1) continue;
    // 是否行首：往前跳过空格/制表符，到文本头或换行即是。
    var atLineStart = false;
    var p = m.start - 1;
    while (p >= 0) {
      final ch = normalized[p];
      if (ch == ' ' || ch == '\t') {
        p -= 1;
        continue;
      }
      atLineStart = ch == '\n' || ch == '\r';
      break;
    }
    if (p < 0) atLineStart = true;
    final c = _Candidate(
      start: m.start,
      markerEnd: m.end,
      number: number,
      hint: hint,
      atLineStart: atLineStart,
      weakForm: weakForm,
      isDotted: isDotted,
    );
    // 题型标记 +3。
    if (hint != null) {
      c.score += 3;
      c.reasons.add('题型标记 +3');
    }
    // 候选之后的窗口（到下一候选或 600 字内）：选项结构与题干。
    final winStart = m.end;
    final nextStart =
        i + 1 < matches.length ? matches[i + 1].start : normalized.length;
    final winEnd = winStart + 600 < nextStart
        ? winStart + 600
        : nextStart;
    final window = winEnd > winStart
        ? normalized.substring(winStart, winEnd)
        : '';
    if (_hasOptionStructure(window)) {
      c.score += 3;
      c.reasons.add('选项结构 +3');
    }
    final stemText = _stemBeforeOptions(window);
    if (stemText.length >= 4) {
      c.score += 2;
      c.reasons.add('题干完整 +2');
    }
    // 前面 48 字内有上一题答案/解析结束标志 +3。
    final backStart = m.start - 48 < 0 ? 0 : m.start - 48;
    if (backStart < m.start) {
      final back = normalized.substring(backStart, m.start);
      if (RegExp(r'(?:答案|正确答案|解析)[ \t]*[:：]').hasMatch(back)) {
        c.score += 3;
        c.reasons.add('上一题答案/解析 +3');
      }
    }
    // 格式不规范/OCR 歧义的弱标记 -2。
    if (weakForm) {
      c.score -= 2;
      c.reasons.add('格式不规范 -2');
    }
    // 疑似年份/句中数字 -3：行中出现且无题型标记，或 1900–2099 且无题型标记。
    if (hint == null &&
        (!atLineStart || (number >= 1900 && number <= 2099))) {
      c.score -= 3;
      c.reasons.add('疑似年份/句中数字 -3');
    }
    // 孤立题号（标记后没有题干）-3。
    if (stemText.isEmpty) {
      c.score -= 3;
      c.reasons.add('孤立题号 -3');
    }
    candidates.add(c);
  }
  return candidates;
}

/// 窗口里有没有选项结构：A、B 两个标记按序出现，或「正确/错误」成对出现。
bool _hasOptionStructure(String window) {
  if (window.contains('正确') && window.contains('错误')) return true;
  final matches = _optionMark.allMatches(window).toList();
  var seenA = false;
  for (final m in matches) {
    final letter = m.group(1);
    if (letter == 'A') {
      seenA = true;
    } else if (letter == 'B' && seenA) {
      return true;
    }
  }
  return false;
}

/// 窗口里第一个选项标记/答案行之前的文字（即题干），换行折成空格。
String _stemBeforeOptions(String window) {
  final optionAt = _optionMark.firstMatch(window)?.start;
  final answerAt =
      RegExp(r'(?:答案|正确答案)[ \t]*[:：]').firstMatch(window)?.start;
  var end = window.length;
  if (optionAt != null && optionAt < end) end = optionAt;
  if (answerAt != null && answerAt < end) end = answerAt;
  return window.substring(0, end).replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// 连续性补分 + 阈值过滤：≥7 高置信切题；4–6 待确认（照样切，标出来）；
/// <4 不切。跳号/重复号不以连续性为必要条件。
List<_Candidate> _selectBoundaries(List<_Candidate> candidates) {
  final accepted = <_Candidate>[];
  int? lastNumber;
  for (final c in candidates) {
    var continuity = 0;
    if (lastNumber == null) {
      // 首题没有前文可佐证，不看连续性，直接给分。
      continuity = 2;
      c.reasons.add('首题不计连续 +2');
    } else if (c.number == lastNumber + 1) {
      continuity = 2;
      c.reasons.add('题号连续 +2');
    } else if (c.number == 1) {
      // 分节后题号从 1 重排。
      continuity = 2;
      c.reasons.add('题号从 1 重排 +2');
    } else if (c.number > lastNumber) {
      continuity = 1;
      c.reasons.add('题号递增 +1');
    }
    c.score += continuity;
    // 行首点号题号最弱：没题型、没连续性、前面也没答案行时不认，
    // 防正文年份/序号误切。只在已切出过题界之后启用：文档第一题
    // （如模板的「1.」）没有前文可佐证，光靠选项结构就该认。
    if (c.isDotted &&
        c.hint == null &&
        continuity == 0 &&
        lastNumber != null &&
        c.number != 1 &&
        c.score - continuity < 6) {
      c.score -= 2;
      c.reasons.add('行首点号弱佐证 -2');
    }
    if (c.score >= 7) {
      c.pending = false;
      accepted.add(c);
      lastNumber = c.number;
    } else if (c.score >= 4) {
      c.pending = true;
      accepted.add(c);
      lastNumber = c.number;
    }
  }
  return accepted;
}

/// 把切题评分明细挂到一道题上（仅内存，不进数据库）。
Question _attachParseInfo(Question question, _Candidate c) {
  return Question(
    id: question.id,
    assignmentId: question.assignmentId,
    type: question.type,
    stem: question.stem,
    options: question.options,
    answer: question.answer,
    points: question.points,
    sortOrder: question.sortOrder,
    parseScore: c.score,
    parseReasons: List<String>.from(c.reasons),
    parsePending: c.pending,
  );
}

List<Question> parseFormattedText(String text) {
final normalized = _normalize(text);
final boundaries = _selectBoundaries(_findCandidates(normalized));
if (boundaries.isEmpty) {
throw FormatException('没找到题号，请按“题号开头、一行一道题”的格式写（见 docs/IMPORT_TEMPLATES.md）');
}

final questions = <Question>[];
for (var i = 0; i < boundaries.length; i++) {
final start = boundaries[i].markerEnd;
final end = i + 1 < boundaries.length
? boundaries[i + 1].start
: normalized.length;
final block = normalized.substring(start, end).trim();
if (block.isEmpty) continue;
// 一块里粘了两道题时（无标记粘连），尽量劈成两道；劈不开就原样保留一道。
final split = _parseBlockWithSplit(block, questions.length);
// 切题评分明细挂在劈开后的第一道题上（粘连劈开的第二道是无标记题，不挂分）。
for (var j = 0; j < split.length; j++) {
questions.add(j == 0 ? _attachParseInfo(split[j], boundaries[i]) : split[j]);
}
}

if (questions.isEmpty) {
throw FormatException('没有解析到题目，请检查文件格式（见 docs/IMPORT_TEMPLATES.md）');
}
return questions;
}

/// 解析单个块（题号标记之后到下一题号之前的一段），返回一道题；
/// 题干为空时返回 null（调用方跳过）。
Question? _parseBlock(String block, int sortOrder) {
var working = block;
var answer = '';

// 1) 先抠答案行。字母答案优先；字母不匹配时按填空文字答案收。
final answerMatch = _answerLine.firstMatch(working);
if (answerMatch!= null) {
answer = answerMatch
.group(1)!
.replaceAll(RegExp(r'[\s,，、]'), '')
.toUpperCase();
working = working.replaceFirst(_answerLine, '').trim();
} else {
final fillMatch = _fillAnswerLine.firstMatch(working);
if (fillMatch!= null) {
final candidate = fillMatch.group(1)!.trim();
// 排除“答案：”后面跟的是解析等说明文字的极端情况：只收较短的答案。
if (candidate.isNotEmpty && candidate.length <= 40) {
answer = candidate;
working = working.replaceFirst(_fillAnswerLine, '').trim();
}
}
}

// 2) 没答案行时，认题干末尾的（B）。
if (answer.isEmpty) {
final bracket = _bracketAnswer.firstMatch(working);
if (bracket!= null) {
answer = bracket.group(1)!;
working = working.replaceFirst(_bracketAnswer, '').trim();
}
}

// 3) 抠选项：按 A. B. C. D. E. 标记切分，标记之间即选项内容。
final optionMatches = _optionMark.allMatches(working).toList();
final options = <String>[];
String stem;
if (optionMatches.length >= 2) {
stem = working.substring(0, optionMatches.first.start).trim();
for (var j = 0; j < optionMatches.length; j++) {
final s = optionMatches[j].end;
final e = j + 1 < optionMatches.length
? optionMatches[j + 1].start
: working.length;
final content = working.substring(s, e).trim();
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
stem = working;
}
} else {
stem = working;
}

// 题干里残留的换行折成空格；多余的“答案”残行已在上面剥掉。
stem = stem.replaceAll(RegExp(r'\s*\n\s*'), ' ').trim();
if (stem.isEmpty) return null;

final type = options.length >= 2
? QuestionType.choice
: QuestionType.fill;
// 填空题答案若是字母串（如答案 B）也按文字保留，不做校验。
return _build(
type: type,
stem: stem,
options: options,
answer: answer,
points: 5,
sortOrder: sortOrder,
);
}

/// 一块文本里有几个答案行（“答案：”/“正确答案：”开头的行）。
int _countAnswerLines(String text) {
return RegExp(r'(?:答案|正确答案)\s*[:：]').allMatches(text).length;
}

/// 文本里是否有一套完整的 A–D 选项标记（分隔符形式，按序出现）。
bool _hasFullOptionSet(String text) {
final matches =
RegExp(r'([ABCDE])[ \t]*[.、．:：]').allMatches(text).toList();
const letters = ['A', 'B', 'C', 'D'];
var next = 0;
for (final m in matches) {
if (m.group(1) == letters[next]) {
next += 1;
if (next >= 4) return true;
}
}
return false;
}

/// 一道题是否粘连嫌疑：块里有多个答案行，或选项里混进了下一题的内容
/// （选项中出现“答案”或题号标记）。只在这两种情况触发劈开尝试。
bool _isAdhesionSuspect(Question question, String block) {
if (_countAnswerLines(block) >= 2) return true;
for (final option in question.options) {
if (option.contains('答案') || _questionMark.hasMatch(option)) return true;
}
return false;
}

/// 解析一块文本，粘连嫌疑时尝试无标记启发式劈开（刷题 App 8.ipa 同款，纯规则）。
///
/// 劈法：块内有 ≥2 个答案行时，从第一个答案行之后第一个非空行处劈开；
/// 后半部分必须有完整选项集（A–D 齐全）与至少 1 个答案行，且重解析后
/// 后半部分不再可疑，否则放弃劈开、原样保留一道。
/// 注意：没有 AI 复核——劈不开就保留原样，不强行入库两道题。
List<Question> _parseBlockWithSplit(String block, int sortOrder) {
final question = _parseBlock(block, sortOrder);
if (question == null) return <Question>[];
if (!_isAdhesionSuspect(question, block)) return <Question>[question];
final split = _trySplitUnmarked(block, sortOrder);
return split ?? <Question>[question];
}

/// 无标记粘连启发式劈开：块内 ≥2 个答案行时，尝试把第二题劈出来。
List<Question>? _trySplitUnmarked(String block, int sortOrder) {
final answerLines =
RegExp(r'(?:答案|正确答案)[ \t]*[:：][^\n]*').allMatches(block).toList();
if (answerLines.length < 2) return null;
// 第二题题干起点：第一个答案行之后第一个非空行行首（跳过空行）。
var offset = answerLines[0].end;
int? stemStart;
final rest = block.substring(offset);
for (final line in rest.split('\n')) {
final trimmed = line.trim();
if (trimmed.isEmpty) {
offset += line.length + 1;
continue;
}
stemStart = offset;
break;
}
if (stemStart == null || stemStart >= block.length) return null;
final firstPart = block.substring(0, stemStart).trim();
final secondPart = block.substring(stemStart);
if (!_hasFullOptionSet(secondPart)) return null;
if (_countAnswerLines(secondPart) < 1) return null;
final first = _parseBlock(firstPart, sortOrder);
final second = _parseBlock(secondPart, sortOrder + 1);
if (first == null || second == null) return null;
// 第二部分仍可疑（比如还粘着第三题）→ 放弃劈开，原样保留。
if (_countAnswerLines(secondPart) >= 2) return null;
if (second.stem.length < 4) return null;
for (final option in second.options) {
if (option.contains('答案') || _questionMark.hasMatch(option)) return null;
}
return <Question>[first, second];
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
