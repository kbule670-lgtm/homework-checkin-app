# 导入模板说明

> 老师出题导入的四种模板。Excel / CSV / JSON / txt 全支持；
> Word（.docx）与 PDF 文字版走“文字版解析”，排版见第五节。
> 列名、字段名按下面写，不要改名。

## 一、Excel 模板（.xlsx / .xls）

首行是表头，从第二行起是题目。列定义：

| 列 | 列名 | 说明 |
|----|------|------|
| A | 题干 | 必填 |
| B | 类型 | `choice`（选择）或 `fill`（填空），可空；空时有选项算选择、无选项算填空 |
| C | 选项A | 选择题必填；填空题留空 |
| D | 选项B | 同上 |
| E | 选项C | 同上（可空，如判断类只有 A、B 两项） |
| F | 选项D | 同上 |
| G | 选项E | 可选列，没有可不写 |
| H | 答案 | 选择题写字母（如 `B`）；填空题写文字答案；可空（空着的题会保留下来，发作业前补） |
| I | 分值 | 数字，可空，默认 5 |

例题（3 道）：

| 题干 | 类型 | 选项A | 选项B | 选项C | 选项D | 答案 | 分值 |
|------|------|-------|-------|-------|-------|------|------|
| 下列哪个单词的意思是“环境”？ | choice | environment | envelope | episode | equipment | A | 5 |
| The Olympic Games ______ every four years. | choice | hold | are held | held | holding | B | 5 |
| 请写出 protect 的名词形式：______ | fill | | | | | protection | 5 |

## 二、CSV 模板（.csv）

列定义与 Excel 完全一致，首行表头：

```csv
题干,类型,选项A,选项B,选项C,选项D,答案,分值
下列哪个单词的意思是“环境”？,choice,environment,envelope,episode,equipment,A,5
The Olympic Games ______ every four years.,choice,hold,are held,held,holding,B,5
请写出 protect 的名词形式：______,fill,,,,,protection,5
```

注意：
- 题干或选项里有逗号时，整个字段用英文双引号包起来，如 `"Hello, world"`。
- 从 Excel/WPS 另存为 CSV 时建议选 UTF-8 编码；GBK 编码的 CSV 也能读，
  但请尽量用 UTF-8，避免生僻字乱码。

## 三、JSON 模板（.json）

顶层为数组，每项字段：`stem`（题干）、`type`（choice/fill，可空）、
`options`（选项数组，可空）、`answer`（答案，可空）、`points`（分值，可空，默认 5）。

```json
[
  {
    "stem": "下列哪个单词的意思是“环境”？",
    "type": "choice",
    "options": ["environment", "envelope", "episode", "equipment"],
    "answer": "A",
    "points": 5
  },
  {
    "stem": "The Olympic Games ______ every four years.",
    "type": "choice",
    "options": ["hold", "are held", "held", "holding"],
    "answer": "B",
    "points": 5
  },
  {
    "stem": "请写出 protect 的名词形式：______",
    "type": "fill",
    "options": [],
    "answer": "protection",
    "points": 5
  }
]
```

## 四、txt 文字版模板（.txt）

一行一道题，题号开头（`1.` / `1、` / `[1]` / `第1题` 都认），
选项可分行、可挤在一行，答案写在题末：

```text
1. 下列哪个单词的意思是“环境”？
A. environment B. envelope C. episode D. equipment
答案：A

2. The Olympic Games ______ every four years.
A. hold
B. are held
C. held
D. holding
答案：B

3. 请写出 protect 的名词形式：______
答案：protection
```

答案写法三种都认：`答案：B`、`答案 B`、题干后直接标 `（B）`。
缺答案的题会保留下来（answer 为空），发作业前记得补。

## 五、Word / PDF 文字版（.docx / 文字版 PDF）

- Word（.docx）：正文按上面第四节的 txt 排版写，题号开头、答案行结尾，
  导入时先提文字再按同一规则解析。老版 .doc 导不了，请另存为 .docx。
- PDF 文字版：同样按第四节排版，导出 PDF 时确认能选中复制文字
  （能选中 = 有文字层，能导；选不中 = 扫描版，导不了）。
- 扫描版 PDF（手机拍的题、图片拼的）没有文字层，导入会提示
  “这是扫描版 PDF，没有文字层，请转文字版 PDF 再导入”。
