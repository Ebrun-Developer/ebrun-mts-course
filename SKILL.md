---
name: ebrun-mts-course
description:
  获取亿邦动力马蹄社课程信息，支持查询近期课程和指定月份课程表。
  当用户说"马蹄社最近有什么课"、"马蹄社近期课程"、"马蹄社6月课程表"、"马蹄社下个月有什么课程"、"马蹄社当月课程安排"时触发。
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

判断用户属于哪一类查询：

1. 最近课程查询
2. 月份课程表查询

判断规则：

- 如果用户提到“最近”“近期”“最新”等词，走最近课程查询
- 如果用户提到明确月份、当月、下个月、课程表、课程安排等词，走月份课程表查询

若意图不明确，但用户已经明确提到马蹄社课程，默认按最近课程查询。

### 步骤2：读取配置

读取 `references/config.json`，获取：

- `_meta.version`
- `data_source.recent_real_api_url` - 最近课程查询
- `data_source.monthly_real_api_url` - 月份课程表查询

### 步骤3：执行脚本

优先直接调用本 skill 自带脚本，不要临时自己写读取逻辑。

#### 最近课程查询

```bash
python3 scripts/query_courses.py recent --json
```

#### 月份课程表查询

```bash
python3 scripts/query_courses.py month --month 2026-06 --json
```

#### 相对月份查询

```bash
python3 scripts/query_courses.py month --relative next --json
python3 scripts/query_courses.py month --relative current --json
```

如果 Python 不可用，再使用 Shell 包装脚本：

```bash
bash scripts/query_courses.sh recent --json
bash scripts/query_courses.sh month --month 2026-06 --json
```

### 步骤4：版本更新检查

**独立执行，不影响主流程**

在后台异步检查是否有新版本：

1. 优先请求版本接口：`https://www.ebrun.com/_index/ClaudeCode/SkillJson/skill_version.json`
2. 从接口返回的 JSON 对象中读取 `ebrun-mts-course` 字段，作为远端最新版本号
3. 读取 `references/config.json` 中的 `_meta.version` 作为当前版本号
4. 如果远端版本号与 `_meta.version` 不一致：
   - 记录更新可用状态
   - 暂存 `update_url_github` 和 `update_url_gitee`
5. 如果版本接口请求失败：
   - 读取 `references/config.json` 中的 `update_url_github` / `update_url_gitee`
   - 从 GitHub / Gitee 仓库远端读取 `references/config.json`
   - 取远端 `_meta.version` 与本地 `_meta.version` 做比对
   - 如果远端仓库中的版本号不一致，则提示更新
6. 只有当版本接口和远端仓库版本文件都失败时，才视为“当前无法判断是否有更新”
7. `references/config.json` 中的 `check_interval_hours` 用于限制检查频率；如果未到间隔，则优先返回运行时缓存的上次检查结果
8. 运行时缓存不得回写 `references/config.json`，避免污染 skill 安装内容
9. 当显式传入自定义 `--version-url` 时，只能复用同一版本源写入的缓存；不同版本源之间不能混用缓存

**注意**：此步骤失败或超时不会影响主流程，仅记录状态供后续使用。

## Output format 输出格式

### 最近课程查询输出

```markdown
🎓 马蹄社近期课程
获取时间: {current_time}

[{title}]({url})
状态：{status}
时间：{date_text}
地点：{city}
简介：{summary}

...

更多资讯请见[亿邦官网](https://www.ebrun.com/)
```

### 月份课程表输出

```markdown
🗓️ 马蹄社课程表 | {month}
获取时间: {current_time}

[{title}]({url})
状态：{status}
时间：{date_text}
地点：{city}

...

更多资讯请见[亿邦官网](https://www.ebrun.com/)
```

### 指定月份无课程

```markdown
🗓️ 马蹄社课程表 | {month}

该月份当前无已记录课程。

更多资讯请见[亿邦官网](https://www.ebrun.com/)
```

### 更新提示

如果版本检查检测到新版本可用，在结果末尾追加：

```markdown
---
💡 检测到有新版本可用
当前版本：v{current_version}
最新版本：v{latest_version}

如需更新请回复「更新」，或访问：
- [GitHub 发布页]({github_release_url})
- [ClawHub 发布页]({clawhub_release_url})
```

## Failure handling 异常情况处理

| 场景 | 处理方式 |
|------|----------|
| 近期课程接口不可用 | 明确告知当前暂时无法读取近期课程数据 |
| 月份课程接口不可用 | 明确告知当前暂时无法读取月份课程数据 |
| 最近课程不足 20 条 | 返回全部可用课程，不编造补齐 |
| 指定月份无课程 | 告知"该月份当前无已记录课程"，并附课程列表页 |
| 字段缺失 | 缺失字段填"未注明"，不要编造 |
| 版本检查失败 | 静默处理，不影响课程输出 |
| 更新地址仍是占位符 | 不请求占位符地址，只展示配置中的更新提示 |

## Data files 数据文件

| 文件路径 | 用途 |
|----------|------|
| `scripts/fetch_courses.js` | 请求课程接口并输出标准化课程结果 |
| `references/config.json` | 假接口、未来真实接口、查询规则和字段映射配置 |
| `references/version.json` | 技能版本配置 |
