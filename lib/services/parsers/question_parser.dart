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

/// 在一段文字里找一套真正的选项：从 A 起按 A、B、C、D… 连续出现，且每
/// 个选项都有实质内容。题干里的 "A、B、C、D 四瓶溶液" 只是光秃秃的枚
/// 举，标记之间没有内容，接不成序列，不算选项——否则会把选择题毒成填
/// 空，把填空题干从第一个 "A、" 处截断（"维生素" 碎片、"2020年，新冠疫
/// 情在全球大流行。" 被截断），题干以 "A、B、C、D" 开头的题（冬奥会题）
/// 更会因题干为空整道被丢。多套序列并存时取最长的，长度相同取最先出现
/// 的（粘连块里先取第一题的选项）。没有成套选项时返回空列表。
List<RegExpMatch> _findOptionSequence(String text) {
final matches = _optionMark.allMatches(text).toList();
var best = <RegExpMatch>[];
for (var i = 0; i < matches.length; i++) {
if (matches[i].group(1) != 'A') continue;
var j = i;
var expected = 'A';
while (j < matches.length && matches[j].group(1) == expected) {
if (j > i) {
final gap = text.substring(matches[j - 1].end, matches[j].start);
if (gap.trim().isEmpty) break;
}
expected = String.fromCharCode(expected.codeUnitAt(0) + 1);
j++;
}
final seq = matches.sublist(i, j);
if (seq.length < 2) continue;
final afterEnd = j < matches.length ? matches[j].start : text.length;
if (text.substring(matches[j - 1].end, afterEnd).trim().isEmpty) continue;
if (seq.length > best.length) best = seq;
}
return best;
}

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
///
/// 切点还有第二路来源：答案行锚定（见 _findAnswerLineCandidates）。每道题都
/// 以“答案：…”行收尾，答案行之后的第一个非空行就是下一题——不管题号长
/// 什么样。题号只是标签，不决定切不错切；这么改之后，A1./B1./Q1./没题
/// 号都不用再逐个打补丁。数字题号那路只负责没答案的题。
class _Candidate {
  final int start;
  final int markerEnd;
  final int number;
  final String? hint;
  final bool atLineStart;
  final bool weakForm;
  final bool isDotted;
  final bool fromAnswerLine;
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
    this.fromAnswerLine = false,
  });
}

/// 候选标记正则（归一化后括号都是半角）。分组与下面 _findNumberCandidates 一一对应：
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

/// 在归一化文本里找全部数字题号候选（只找、不打分；打分见 _scoreCandidates）。
/// 数字题号是 `1.` / `[1]` / `第1题` 这类标准写法；A1./B1. 之类怪写法不
/// 在这里认——它们走答案行锚定（见 _findAnswerLineCandidates）。
List<_Candidate> _findNumberCandidates(String normalized) {
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
    candidates.add(_Candidate(
      start: m.start,
      markerEnd: m.end,
      number: number,
      hint: hint,
      atLineStart: atLineStart,
      weakForm: weakForm,
      isDotted: isDotted,
    ));
  }
  return candidates;
}

/// 给合并后的候选打分（不含连续性分，连续性由 _selectBoundaries 按顺序补）。
/// 窗口取到下一个候选或 600 字。
void _scoreCandidates(List<_Candidate> candidates, String normalized) {
  for (var i = 0; i < candidates.length; i++) {
    final c = candidates[i];
    // 题型标记 +3。
    if (c.hint != null) {
      c.score += 3;
      c.reasons.add('题型标记 +3');
    }
    // 候选之后的窗口（到下一候选或 600 字内）：选项结构与题干。
    final winStart = c.markerEnd;
    final nextStart =
        i + 1 < candidates.length ? candidates[i + 1].start : normalized.length;
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
    final backStart = c.start - 48 < 0 ? 0 : c.start - 48;
    if (backStart < c.start) {
      final back = normalized.substring(backStart, c.start);
      if (RegExp(r'(?:答案|正确答案|解析)[ \t]*[:：]').hasMatch(back)) {
        c.score += 3;
        c.reasons.add('上一题答案/解析 +3');
      }
    }
    // 格式不规范/OCR 歧义的弱标记 -2。
    if (c.weakForm) {
      c.score -= 2;
      c.reasons.add('格式不规范 -2');
    }
    // 疑似年份/句中数字 -3：行中出现且无题型标记，或 1900–2099 且无题型标记。
    if (c.hint == null &&
        (!c.atLineStart || (c.number >= 1900 && c.number <= 2099))) {
      c.score -= 3;
      c.reasons.add('疑似年份/句中数字 -3');
    }
    // 孤立题号（标记后没有题干）-3。
    if (stemText.isEmpty) {
      c.score -= 3;
      c.reasons.add('孤立题号 -3');
    }
  }
}

/// 行首答案行：`答案：B` / `答案 B` / `答案：1869`（行首才算，题干里提到
/// “答案”两个字不算）。
final _answerLineStart = RegExp(
  r'^[ \t]*(?:答案|正确答案)[ \t]*[:：]?',
  multiLine: true,
);

/// 行首的讲解/注记行：答案行之后跟的是这些行时，不是新题，是上一题的讲解。
final _explanationLineStart = RegExp(
  r'^[ \t]*(?:解析|分析|详解|点评|答案|正确答案|注|附)',
  multiLine: true,
);

/// 一行开头的通用标签长度（只量形状，不认具体写法）：`[12]` / `(3)` /
/// `第3题` / 1–6 位字母数字加分隔符（`A1.` `B1.` `Q1:` `AB12.` `12.` 都
/// 算）。量不到返回 0。注意：这只是“剥标签”和“像不像题”的形状判断，标
/// 签长什么样不决定切不错切——切点证据是答案行。
int _leadingLabelLength(String line) {
  final m = RegExp(
    r'^[ \t]*(?:\[[^\]\n]{1,8}\]|\([^)\n]{1,8}\)|第[^\n]{1,8}题|[A-Za-z0-9]{1,6}[.、．)）\]：:])[ \t]*')
      .firstMatch(line);
  return m?.end ?? 0;
}

/// 答案行锚定的候选切点：每道题都以“答案：…”行收尾，所以答案行之后的第一
/// 个非空行就是下一题的开头——不管题号长什么样（A1./B1./Q1./没题号都
/// 行），文档第一行也一样。题号只是个标签，不该决定切不错切；切点证据
/// 是文档结构（答案行），不是题号写法。这才是认题号的根因修法：之前只
/// 认 `1.` 这类数字题号，遇到 A1. 就得打补丁，B1. 又得再打一个，永远
/// 打不完。讲解行（解析/注）不算新题；没标签、没空、行尾没标点的 stray
/// 句子也不算。
List<_Candidate> _findAnswerLineCandidates(String normalized) {
  final lines = normalized.split('\n');
  final lineStarts = <int>[];
  var offset = 0;
  for (final line in lines) {
    lineStarts.add(offset);
    offset += line.length + 1;
  }
  bool looksLikeQuestion(int li) {
    final line = lines[li];
    final trimmed = line.trim();
    if (trimmed.isEmpty) return false;
    if (_leadingLabelLength(line) > 0) return true;
    if (RegExp(r'_{2,}|_[^_\s]').hasMatch(trimmed)) return true;
    if (trimmed.endsWith(':') ||
        trimmed.endsWith('：') ||
        trimmed.endsWith('?') ||
        trimmed.endsWith('？')) {
      return true;
    }
    // 选项在后面几行：只看本行加后两行，别把下一题的选项算进来。
    final following = <String>[line];
    var j = li + 1;
    while (j < lines.length && following.length < 3) {
      if (lines[j].trim().isNotEmpty) {
        following.add(lines[j]);
      }
      j++;
    }
    return _hasOptionStructure(following.join('\n'));
  }
  final anchorLines = <int>[];
  final firstNonEmpty = lines.indexWhere((l) => l.trim().isNotEmpty);
  if (firstNonEmpty >= 0) anchorLines.add(firstNonEmpty);
  for (var i = 0; i < lines.length; i++) {
    if (!_answerLineStart.hasMatch(lines[i])) continue;
    var j = i + 1;
    while (j < lines.length && lines[j].trim().isEmpty) {
      j++;
    }
    if (j < lines.length) anchorLines.add(j);
  }
  final candidates = <_Candidate>[];
  for (final li in anchorLines) {
    final line = lines[li];
    if (_explanationLineStart.hasMatch(line)) continue;
    if (!looksLikeQuestion(li)) continue;
    final leadingSpaces = line.length - line.trimLeft().length;
    candidates.add(_Candidate(
      start: lineStarts[li] + leadingSpaces,
      markerEnd: lineStarts[li] + _leadingLabelLength(line),
      number: 0,
      hint: null,
      atLineStart: true,
      weakForm: false,
      isDotted: false,
      fromAnswerLine: true,
    ));
  }
  return candidates;
}

/// 合并两路候选，按位置排序；同一行上只留一个，数字题号优先（它带真题
/// 号，答案行锚定的只有合成连续分）。
List<_Candidate> _mergeCandidates(
    List<_Candidate> a, List<_Candidate> b, String normalized) {
  final all = [...a, ...b]..sort((x, y) => x.start.compareTo(y.start));
  final merged = <_Candidate>[];
  for (final c in all) {
    if (merged.isEmpty) {
      merged.add(c);
      continue;
    }
    final last = merged.last;
    final between = normalized.substring(last.start, c.start);
    if (!between.contains('\n')) {
      if (last.fromAnswerLine && !c.fromAnswerLine) {
        merged[merged.length - 1] = c;
      }
      continue;
    }
    merged.add(c);
  }
  return merged;
}

/// 窗口里有没有选项结构：A、B 两个标记按序出现，或「正确/错误」成对出现。
bool _hasOptionStructure(String window) {
  if (window.contains('正确') && window.contains('错误')) return true;
  return _findOptionSequence(window).length >= 2;
}

/// 窗口里第一个选项标记/答案行之前的文字（即题干），换行折成空格。
String _stemBeforeOptions(String window) {
  final seq = _findOptionSequence(window);
  final optionAt = seq.isEmpty ? null : seq.first.start;
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
    if (c.fromAnswerLine) {
      // 答案行锚定的切点：上一题答案行就是最强的连续性证据，不看题号。
      continuity = 2;
      c.reasons.add('答案行后新题 +2');
    } else if (lastNumber == null) {
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
      lastNumber = c.fromAnswerLine ? (lastNumber ?? 0) + 1 : c.number;
    } else if (c.score >= 4) {
      c.pending = true;
      accepted.add(c);
      lastNumber = c.fromAnswerLine ? (lastNumber ?? 0) + 1 : c.number;
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
final merged = _mergeCandidates(
_findNumberCandidates(normalized),
_findAnswerLineCandidates(normalized),
normalized);
_scoreCandidates(merged, normalized);
final boundaries = _selectBoundaries(merged);
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

// 1) 先抠答案行：字母答案与文字答案哪个在前面先出现就认哪个（不能字
// 母优先——一块里粘了 "答案：1869" 和 "答案：A" 两行时，字母优先会错认
// 成后一行的 A，把 1869 漏进题干）。抠完再把块里残留的行首答案行清掉，
// 免得下一题的答案漏进本题题干。
final answerMatch = _answerLine.firstMatch(working);
final fillMatch = _fillAnswerLine.firstMatch(working);
final useLetter = answerMatch != null &&
(fillMatch == null || answerMatch.start <= fillMatch.start);
if (useLetter) {
answer = answerMatch
.group(1)!
.replaceAll(RegExp(r'[\s,，、]'), '')
.toUpperCase();
working = working.replaceFirst(_answerLine, '').trim();
} else if (fillMatch != null) {
var candidate = fillMatch.group(1)!.trim();
// 排除“答案：”后面跟的是解析等说明文字的极端情况：只收较短的答案。
if (candidate.isNotEmpty && candidate.length <= 40) {
// 文字答案若是单个 A-E 字母串（如 "答案b"），转大写，与字母答案一致。
if (RegExp(r'^[A-Ea-e]([,\s、，]*[A-Ea-e])*$').hasMatch(candidate)) {
candidate =
candidate.replaceAll(RegExp(r'[\s,，、]'), '').toUpperCase();
}
answer = candidate;
working = working.replaceFirst(_fillAnswerLine, '').trim();
}
}
// 残留的行首答案行（粘连块里下一题的答案）从题干里清掉；正文里 "答案是…"
// 这种句子不带冒号、不以答案行起首，不会被误删。
working = working
.replaceAll(
RegExp(r'^[ \t]*(?:答案|正确答案)[ \t]*[:：][^\n]*$',
multiLine: true),
'')
.replaceAll(
RegExp(r'^[ \t]*(?:答案|正确答案)[ \t]+[A-Ea-e0-9][^\n]*$',
multiLine: true),
'')
.replaceAll(
RegExp(r'^[ \t]*(?:解析|分析|详解|点评|注|附)[ \t]*[:：][^\n]*$',
multiLine: true),
'')
.trim();

// 2) 没答案行时，认题干末尾的（B）。
if (answer.isEmpty) {
final bracket = _bracketAnswer.firstMatch(working);
if (bracket!= null) {
answer = bracket.group(1)!;
working = working.replaceFirst(_bracketAnswer, '').trim();
}
}

// 3) 抠选项：找一套从 A 起连续、每项都有内容的选项序列；序列本身已保
// 证从 A 起连续，不再需要事后校验与回退。没有成套序列时整段都是题干
// （填空题题干里的 "A、B、C、D" 枚举不再把题干截断）。
final optionMatches = _findOptionSequence(working);
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
return _findOptionSequence(text).length >= 4;
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
// 第二部分得像一道真题：要么有完整选项集（选择题），要么是带空、以冒号
// 或问号收尾的填空题且有答案；解析/分析开头的说明文字不算。
final looksLikeChoice = _hasFullOptionSet(secondPart);
final looksLikeFill = second.answer.isNotEmpty &&
!RegExp(r'^(解析|分析|详解|点评)').hasMatch(second.stem) &&
(RegExp(r'_{2,}|_[^_\s]').hasMatch(second.stem) ||
second.stem.endsWith(':') ||
second.stem.endsWith('：') ||
second.stem.endsWith('?') ||
second.stem.endsWith('？'));
if (!looksLikeChoice && !looksLikeFill) return null;
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
