# ebrun-mts-course

一个用于获取亿邦动力马蹄社课程信息的 Claude Code Skill，支持查询近期课程和指定月份课程表，并返回适合代理或自动化流程消费的结构化结果。

### 项目简介

`ebrun-mts-course` 面向需要快速查看马蹄社课程安排的使用场景，能够根据自然语言中的“近期课程”或“月份课程表”意图，读取亿邦动力对应课程 JSON，并整理为清晰、稳定的输出。

它适合以下任务：

- 查询马蹄社最近有什么课
- 查询某个月份的课程表
- 在上层 Agent、自动化脚本或信息聚合流程中复用课程查询能力

### 主要能力

- 支持识别“最近 / 近期 / 最新”类课程查询
- 支持识别明确月份、当月、下个月、课程表、课程安排等月份查询
- 近期课程查询不做人为截断，接口返回多少条就输出多少条
- 月份课程查询会从按月份分组的上游对象中提取目标月份，并返回标准化结果
- 输出核心字段，包括标题、状态、时间、地点和课程链接
- 内置 Python 与 Shell 两套查询脚本，便于不同运行环境接入
- 提供版本检查脚本，便于判断 skill 是否有可用更新
- 当月份输入不合法时，自动回退到当前月份，并返回明确提示

### 目录结构

```text
ebrun-mts-course/
├── SKILL.md
├── README.md
├── examples.md
├── references/
│   ├── api-reference.md
│   └── config.json
└── scripts/
    ├── query_courses.py
    ├── query_courses.sh
    ├── update.py
    └── update.sh
```

### 触发示例

以下表达适合触发该 skill：

- `马蹄社最近有什么课`
- `最近马蹄社有哪些课程`
- `帮我看看马蹄社近期课程`
- `马蹄社6月份都有什么课程`
- `马蹄社7月课程表`
- `马蹄社下个月有什么课程`
- `马蹄社当月有什么课程`

### 使用方式

#### 1. 通过自然语言调用

在支持 Claude Code Skill 的环境中，可直接使用自然语言描述要查询的课程类型。skill 会自动判断这是“最近课程查询”还是“月份课程表查询”。

#### 2. 通过脚本直接调用

优先使用内置脚本，而不是在外部重复编写请求逻辑。

Python 脚本当前兼容 `Python 3.6+`。如果环境里没有可用的 Python 3，或 `python3` 实际版本低于 3.6，建议直接使用同目录下的 Shell 降级脚本。

以下命令示例默认在当前 skill 根目录执行。

```bash
# 查询近期课程
python3 scripts/query_courses.py recent --json

# 查询指定月份课程表
python3 scripts/query_courses.py month --month 2026-07 --json

# 查询当前月份课程表
python3 scripts/query_courses.py month --relative current --json

# Python 不可用或版本低于 3.6 时使用 Shell 版本
bash scripts/query_courses.sh recent --json
```

#### 3. 检查更新

```bash
# 常规检查
python3 scripts/update.py --json

# 强制忽略检查间隔
python3 scripts/update.py --json --force

# Python 不可用或版本低于 3.6 时使用 Shell 版本
bash scripts/update.sh --json
```

### 输出说明

默认返回适合进一步处理的结构化课程数据。

近期课程查询的典型字段包括：

- `title`
- `url`
- `status`
- `date_text`
- `city`
- `summary`

月份课程查询的脚本输出除了 `courses` 数组外，还包括：

- `requested_month`
- `resolved_month`
- `month_input_valid`
- `notice`

在面向终端用户展示时，可进一步格式化为 Markdown 课程列表或课程简报。

### 适用边界

推荐用于：

- 马蹄社近期课程查询
- 某个月份课程表查看
- 自动化课程信息收集与汇总

不建议用于：

- 非马蹄社课程或活动查询
- 报名、支付、代填表单或提交个人信息
- 个性化课程推荐、学习路径规划
- 读取报名数据、学习进度或站外来源

### 原创性与隐私说明

- 本 README 基于本仓库内的 `SKILL.md`、示例和脚本能力重新整理编写，不直接复制内部说明文本。
- 文档仅描述公开可用的功能、目录与使用方式，不暴露任何个人隐私信息、账号信息、Cookie 或凭证内容。
- 示例命令与示例查询仅用于说明调用方式，不包含用户数据或业务敏感内容。
- 如将本 skill 接入生产流程，建议继续遵循最小化日志、最小化输入保留和凭证隔离原则。

## English

### Overview

`ebrun-mts-course` is a Claude Code skill for retrieving Ebrun MTS course information. It supports both recent-course queries and month-based schedule queries, and returns clean structured data for downstream use.

Typical use cases include:

- checking what recent MTS courses are available
- reading the course schedule for a specific month
- integrating MTS course retrieval into an agent or automation workflow

### Key Features

- Intent detection for recent-course queries
- Intent detection for month-based schedule queries
- No artificial truncation for recent-course results
- Structured month query output with resolved month metadata
- Structured outputs with title, status, date, city, and source URL
- Both Python and shell query scripts for flexible integration
- Built-in update checker for version awareness
- Automatic fallback to the current month when the input month is invalid

### Project Layout

```text
ebrun-mts-course/
├── SKILL.md
├── README.md
├── examples.md
├── references/
│   ├── api-reference.md
│   └── config.json
└── scripts/
    ├── query_courses.py
    ├── query_courses.sh
    ├── update.py
    └── update.sh
```

### Example Triggers

This skill is designed for requests such as:

- `What recent MTS courses are available`
- `Show me recent MTS courses`
- `What courses are in July`
- `Show me the MTS course schedule for this month`
- `What courses are next month`

### Usage

#### 1. Natural language invocation

In a Claude Code environment that supports skills, users can ask about recent courses or a monthly course schedule in plain language. The skill resolves the intent automatically.

#### 2. Direct script usage

Prefer the built-in scripts instead of reimplementing request logic externally.

The following commands assume you are running them from the skill root directory.

```bash
python3 scripts/query_courses.py recent --json
python3 scripts/query_courses.py month --month 2026-07 --json
python3 scripts/query_courses.py month --relative current --json
bash scripts/query_courses.sh recent --json
```

#### 3. Version check

```bash
python3 scripts/update.py --json
python3 scripts/update.py --json --force
```

### Output

The skill is designed to return structured course data that is easy to format into markdown lists, briefings, or higher-level workflows.

Recent-course results typically include:

- `title`
- `url`
- `status`
- `date_text`
- `city`

Month query results also include:

- `requested_month`
- `resolved_month`
- `month_input_valid`
- `notice`
- `courses`

### Scope

Recommended for:

- recent MTS course retrieval
- monthly course schedule lookup
- automation and agent-based course aggregation

Not intended for:

- non-MTS course or event topics
- sign-up, payment, or form submission
- personalized course recommendation
- private enrollment or learning-progress data

### Originality and Privacy Notes

- This README is newly written from the repository materials and is not a direct copy of the internal skill instructions.
- It documents only functional behavior, file structure, and usage patterns, without exposing personal data, credentials, cookies, or other sensitive information.
- Example prompts and commands are generic and contain no user-specific or operationally sensitive content.
- For production use, it is still best to keep logs minimal, isolate credentials, and avoid retaining unnecessary request data.
