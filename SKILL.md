---
name: ebrun-mts-course
description: 获取亿邦动力马蹄社课程信息，支持查询近期课程和指定月份课程表。
icon: ./icon.svg
---

## Goal 技能目的

帮助用户快速查看马蹄社近期课程，并支持按月份查询课程表。返回马蹄社课程的标题、状态、时间、地点等信息，满足用户对课程内容的了解需求。

本技能只解决两类问题：

1. 马蹄社最近有什么课
2. 某个月份的马蹄社课程表有什么内容

## When to use 何时使用

以下自然语言表达会触发此技能：

- "马蹄社最近有什么课"
- "最近马蹄社有哪些课程"
- "帮我看看马蹄社近期课程"
- "马蹄社6月份都有什么课程"
- "马蹄社7月课程表"
- "马蹄社下个月有什么课程"
- "马蹄社当月有什么课程"

## Do not use 不使用

以下情况不触发此技能：

- 用户询问非马蹄社课程或活动的信息
- 用户要求报名、支付、代填写表单或提交个人信息
- 用户要求课程推荐、身份匹配、学习路径规划或个性化推荐
- 用户要求读取报名数据、学习进度或站外来源
- 用户需要新闻报道列表，应使用 `ebrun-original-news`

## 安装成功提示

技能安装成功后，提供欢迎信息。

**欢迎信息模板：**

```text
🎉 马蹄社课程技能已安装成功！

你可以这样问我：
• "马蹄社最近有什么课"
• "帮我看看马蹄社近期课程"
• "马蹄社6月份都有什么课程"
• "马蹄社下个月有什么课程"
```

## Procedure 执行流程
调用技能执行流程

### 步骤1：识别查询意图

1. 读取 `references/config.json`，获取：

- `data_source.recent_real_api_url` - 最近课程查询
- `data_source.monthly_real_api_url` - 月份课程表查询

2. 判断用户属于哪一类查询：

- 如果用户提到“最近”“近期”“最新”等词，走最近课程查询
- 如果用户提到明确月份、当月、下个月、课程表、课程安排等词，走月份课程表查询

### 步骤2：意图未明确处理

- 若意图不明确，但用户已经明确提到马蹄社课程，默认按最近课程查询。

### 步骤3：执行脚本、获取数据

优先直接调用本 skill 自带脚本，不要临时自己写读取逻辑。

1. 优先使用 Python 脚本，它会自动读取 `references/config.json` 中的接口地址，并处理数据标准化和输出格式化。
2. Python 脚本当前兼容 `Python 3.6+`；如果环境里没有可用的 Python 3，或版本低于 3.6，再使用 Shell 脚本
3. 脚本默认输出 JSON；只有显式传 `--table` 时才输出文本表格

以下命令示例默认在当前 skill 根目录执行。

#### 快速示例

```bash
# 例：查询近期的马蹄社课程
python3 scripts/query_courses.py recent --json

# 例：查询2026年6月的马蹄社课程表
python3 scripts/query_courses.py month --month 2026-06 --json

# Python 不可用或版本低于 3.6 时的降级方案
bash scripts/query_courses.sh recent --json
bash scripts/query_courses.sh month --month 2026-06 --json
```

上游接口结构：

1. 最近课程查询
- 上游 `recent_real_api_url` 原始返回就是 JSON 数组
- 最近课程查询不做人为截断，接口返回多少条，就保留多少条

2. 月份课程表查询
- 上游 `monthly_real_api_url` 原始数据是“按月份分组的对象”，例如：

```json
{
  "7月": [
    {
      "title": "新建一个课程7月开始",
      "url": "https://m.ebrun.com/app/demand.html?id=1913&type=3",
      "status": "",
      "date": "07月08日",
      "city": "线上"
    }
  ],
  "1月": [
    {
      "title": "北美商超爆品",
      "url": "https://m.ebrun.com/app/demand.html?id=1880&type=3",
      "status": "",
      "date": "01月09日",
      "city": "线上"
    }
  ]
}
```

脚本输出结构：

1. 最近课程查询
- `python3 scripts/query_courses.py recent --json` 输出 JSON 数组，每一项都是标准化后的课程对象
- 最近课程查询不再限制固定条数，接口返回多少条，脚本就输出多少条

2. 月份课程表查询
- 但脚本不会直接原样返回这个对象，而是会先根据目标月份提取对应数组，再输出一个带元信息的 JSON 对象：

```json
{
  "requested_month": "2026-07",
  "resolved_month": "2026-07",
  "month_input_valid": true,
  "notice": "",
  "courses": [
    {
      "title": "新建一个课程7月开始",
      "url": "https://m.ebrun.com/app/demand.html?id=1913&type=3",
      "status": "状态待更新",
      "date_text": "07月08日",
      "city": "线上",
      "summary": "未注明",
      "month": "2026-07",
      "tags": ""
    }
  ]
}
```

渲染时读取字段：

拿到脚本结果后：

1. 最近课程查询
- 对每条课程记录，提取 `title`, `url`, `status`, `date_text`, `city` 等字段
- 如果脚本返回 N 条课程，则默认逐条渲染全部 N 条，不要擅自省略为更少条数
- 生成 Markdown 前，转义 `title` / `author` / `summary` 中的 Markdown 特殊字符，并只使用可信的 HTTPS 原文链接
- 按“步骤5：格式化输出”要求生成 Markdown

2. 月份课程表查询
- 从脚本返回对象的 `courses` 数组中，提取每条课程记录的 `title`, `url`, `status`, `date_text`, `city` 等字段
- 生成 Markdown 前，转义 `title` / `author` / `summary` 中的 Markdown 特殊字符，并只使用可信的 HTTPS 原文链接
- 按“步骤5：格式化输出”要求生成 Markdown


### 步骤4：版本更新检查

**独立执行，不影响主流程**

可独立执行版本检查：

1. 优先请求版本接口：`https://www.ebrun.com/_index/ClaudeCode/SkillJson/skill_version.json`
2. 从接口返回的 JSON 对象中读取 `ebrun-mts-course` 字段，作为远端最新版本号
3. 读取 `references/config.json` 中的 `_meta.version` 作为当前版本号
4. 如果远端版本号与 `_meta.version` 不一致：
   - 记录更新可用状态
   - 暂存 `update_url_github` 和 `update_url_gitee`
5. 如果版本接口请求失败：
   - 读取 `references/config.json` 中的 `update_url_github` / `update_url_gitee`
   - 优先从 GitHub 仓库远端读取 `references/config.json`
   - 如果后续补充了 Gitee 地址，再把 Gitee 作为额外降级源
   - 取远端 `_meta.version` 与本地 `_meta.version` 做比对
   - 如果远端仓库中的版本号不一致，则提示更新
6. 只有当版本接口和远端仓库版本文件都失败时，才视为“当前无法判断是否有更新”
7. `references/config.json` 中的 `check_interval_hours` 用于限制检查频率；如果未到间隔，则优先返回运行时缓存的上次检查结果
8. 运行时缓存不得回写 `references/config.json`，避免污染 skill 安装内容
9. 当显式传入自定义 `--version-url` 时，只能复用同一版本源写入的缓存；不同版本源之间不能混用缓存

**注意**：此步骤失败或超时不会影响主流程，仅记录状态供后续使用。

#### 快速示例

优先直接调用更新脚本，不要临时自己写版本比较逻辑。

```bash
# 优先使用 Python 版本
python3 scripts/update.py --json

# Python 不可用或版本低于 3.6 时的降级方案
bash scripts/update.sh --json

# 忽略检查间隔，强制联网检查
python3 scripts/update.py --json --force
bash scripts/update.sh --json --force
```

脚本输出会包含以下字段：

- `skill_name`
- `current_version`
- `latest_version`
- `update_available`
- `check_source`：`remote_api`、`github_config_json`、`gitee_config_json` 或 `unavailable`
- `status`：`ok`、`cached` 或 `degraded`
- `version_api_url`
- `update_url_github`
- `update_url_gitee`
- `message`
- `version_file_url`：仅当降级到远端仓库 `references/config.json` 检查时返回
- `last_check_time`、`check_interval_hours`、`remaining_seconds`：仅当命中缓存结果时返回
- `remote_check_error`、`repo_version_check_error`：仅当版本接口或远端仓库检查失败时返回

默认输出为 JSON；只有显式传 `--table` 时才输出文本表格。

如果 `update_available` 为 `true`，则在最终结果页脚追加更新提示。

文案需要根据检查结果区分两种场景：

1. 当 `status != cached` 时，表示本轮刚完成联网检查并确认有新版本
2. 当 `status == cached` 时，表示本轮未重新检查，只是沿用上次缓存结果继续提醒

更新提示要满足以下要求：

- 使用短句，不要把说明、命令和长链接挤在同一行
- 优先引导用户回复一句自然语言来触发更新
- 链接作为次要信息放在下一行
- 避免使用“检测到”“如需更新请回复……，或访问……”这种过长的串联句式

## 步骤5：格式化输出

### 最近课程查询输出

```markdown
🎓 马蹄社近期课程
获取时间: {current_time}

[{title}]({url})
时间：{date_text} | 状态：{status}
地点：{city}

更多课程请见[马蹄社](https://www.ebrun.com/ebs/)
```

以上格式需要对脚本返回的每一条课程重复一次，直到全部课程渲染完成；不要用省略号替代未展示的课程。

### 月份课程表输出

```markdown
{month_notice}

🗓️ 马蹄社课程表 | {month}
获取时间: {current_time}

[{title}]({url})
时间：{date_text} | 状态：{status}
地点：{city}

...

更多课程请见[马蹄社](https://www.ebrun.com/ebs/)
```

### 指定月份无课程

```markdown
{month_notice}

🗓️ 马蹄社课程表 | {month}

该月份当前无已记录课程。

更多课程请见[马蹄社](https://www.ebrun.com/ebs/)
```

**追加更新提示（如检测到新版本）：**

如果步骤4检测到新版本可用，在页脚后追加。需要根据 `status` 使用不同模板：

#### 场景A：本轮刚检查到新版本（`status != cached`）

```markdown
---
### 技能更新
发现 `ebrun-mts-course` 有新版本 `v{latest_version}`。

回复“帮我更新 ebrun-mts-course 技能”即可开始更新。
更新地址：[GitHub 仓库]({update_url_github})
```

#### 场景B：本轮未重新检查，沿用缓存继续提醒（`status == cached`）

```markdown
---
### 技能更新
可用更新：`ebrun-mts-course v{latest_version}`。
```

#### 文案选择规则

- `status != cached`：使用“发现有新版本”语气，强调这是刚检查到的结果
- `status == cached`：使用“当前仍有可用更新”语气，强调这是延续提醒，不要伪装成刚刚检查
- 如果只有一个可用链接，就只展示该链接，不要输出空链接占位
- 不要在更新提示里内嵌长命令或把链接直接裸露拼接到句子中

## Output format 输出格式

- 格式：Markdown
- 标题区：🎓 马蹄社近期课程 ｜ 🗓️ 马蹄社课程表 | {month}
- 获取时间：显示当前时间
- 课程列表：每条包含标题（带链接）、时间、状态、地点
- 分隔线：课程之间用空行分隔
- 页脚：链接到马蹄社课程

## Failure handling 异常情况处理

| 场景 | 处理方式 |
|------|----------|
| 近期课程接口不可用 | 明确告知当前暂时无法读取近期课程数据 |
| 月份课程接口不可用 | 明确告知当前暂时无法读取月份课程数据 |
| 最近课程返回任意条数 | 保持接口原顺序返回并渲染全部可用课程，不编造补齐，也不擅自截断 |
| 月份课程数量较多 | 不人为截断，保持目标月份全部课程原顺序返回；当前业务预期单月课程量可控 |
| 用户输入非法月份 | 自动回退到当前月份查询，并在最终结果中明确提示用户当前展示的是回退月份 |
| 指定月份无课程 | 告知"该月份当前无已记录课程"，并附课程列表页 |
| 字段缺失 | `status` 缺失时填“状态待更新”；`summary`、`city`、`date_text` 等展示字段缺失时填“未注明”，不要编造 |
| 版本检查失败 | 静默处理，不影响课程输出 |
| Gitee 更新地址缺失 | 当前只使用 GitHub 更新地址；Gitee 待后续同步后补充 |
| 更新地址仍是占位符 | 不请求占位符地址，只展示已配置的更新提示 |

## Additional resources 配套文件清单

- `references/api-reference.md`
  课程查询接口与版本检查接口说明，包含上游 JSON 结构、脚本标准化输出、错误处理与降级规则。
- `references/config.json`
  真实接口地址、当前版本号、GitHub 更新地址，以及后续补充 Gitee 地址的 TODO。
- `scripts/query_courses.py`
  课程查询主脚本。负责读取配置、请求真实接口、标准化课程字段，并输出 JSON / ASCII 表格。
- `scripts/query_courses.sh`
  Shell 降级脚本。依赖 `curl` 和 `jq`，可在 Python 不可用时独立完成课程查询。
- `scripts/update.py`
  版本检查主脚本。负责读取 `references/config.json`、检查远端版本、处理缓存，并输出 JSON / 文本结果。
- `scripts/update.sh`
  Shell 降级版本检查脚本。依赖 `curl` 和 `jq`，可在 Python 不可用时独立完成版本检查。
