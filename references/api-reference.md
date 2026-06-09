# API 参考文档 — 亿邦马蹄社课程 JSON 接口

## 接口概览

本 Skill 依赖两份亿邦课程 JSON：

1. 近期课程列表：`ebs_course_all.json`
2. 按月份分组的课程表：`ebs_course_year.json`

优先直接使用 Skill 自带脚本访问这些接口，而不是在运行时重写抓取逻辑。

## 近期课程接口

### 接口基础信息

| 属性 | 值 |
|------|----|
| URL | `https://www.ebrun.com/_index/ClaudeCode/SkillJson/ebs_course_all.json` |
| 方法 | `GET` |
| 认证 | 无需认证 |
| 推荐请求头 | `User-Agent`、`Accept`、`Referer` |
| 响应格式 | `application/json` |
| 顶层结构 | `array` |
| Skill 读取条数 | 不做人为截断，接口返回多少条就输出多少条 |

### 请求示例

```http
GET https://www.ebrun.com/_index/ClaudeCode/SkillJson/ebs_course_all.json
```

也可以优先通过 Skill 自带脚本访问：

```bash
python3 scripts/query_courses.py recent --json
bash scripts/query_courses.sh recent --json
```

默认输出为 JSON；只有显式传 `--table` 时才输出表格文本。

### 响应结构

接口成功时返回 JSON 数组，每个元素代表一条课程。

| 字段 | 类型 | 说明 | 示例 |
|------|------|------|------|
| `title` | string | 课程标题 | `"再次新建一个本月报名的额"` |
| `url` | string | 课程详情链接 | `"https://m.ebrun.com/app/demand.html?id=1914&type=3"` |
| `status` | string | 课程状态文案 | `"立即报名"` |
| `date` | string | 课程时间文案 | `"07/07 00:00"` |
| `city` | string | 课程地点 | `"线上"` |

### 完整响应示例

```json
[
  {
    "title": "再次新建一个本月报名的额",
    "url": "https://m.ebrun.com/app/demand.html?id=1914&type=3",
    "status": "立即报名",
    "date": "07/07 00:00",
    "city": "线上"
  },
  {
    "title": "新建一个课程7月开始",
    "url": "https://m.ebrun.com/app/demand.html?id=1913&type=3",
    "status": "立即报名",
    "date": "07/08 00:00",
    "city": "线上"
  }
]
```

### 脚本标准化输出

`python3 scripts/query_courses.py recent --json` 与 `bash scripts/query_courses.sh recent --json` 输出仍是数组，但会先做标准化；不会额外截断近期课程条数。

| 输出字段 | 说明 |
|------|------|
| `title` | 标题；缺失时填 `未注明` |
| `url` | 原始链接文本 |
| `status` | 状态；缺失时填 `状态待更新`；原始值为 `立即报名` 时统一映射为 `正在报名` |
| `date_text` | 优先读取 `date_text`，否则回退到 `date` |
| `city` | 地点；缺失时填 `未注明` |
| `summary` | 摘要；当前课程接口通常没有该字段，脚本会填 `未注明` |
| `month` | 最近课程查询固定为空字符串 |
| `tags` | 标签数组会转成逗号分隔字符串；缺失时为空字符串 |

## 月份课程表接口

### 接口基础信息

| 属性 | 值 |
|------|----|
| URL | `https://www.ebrun.com/_index/ClaudeCode/SkillJson/ebs_course_year.json` |
| 方法 | `GET` |
| 认证 | 无需认证 |
| 推荐请求头 | `User-Agent`、`Accept`、`Referer` |
| 响应格式 | `application/json` |
| 顶层结构 | `object` |
| 分组方式 | 以中文月份标签作为 key，例如 `1月`、`7月` |

### 请求示例

```http
GET https://www.ebrun.com/_index/ClaudeCode/SkillJson/ebs_course_year.json
```

也可以优先通过 Skill 自带脚本访问：

```bash
python3 scripts/query_courses.py month --month 2026-07 --json
python3 scripts/query_courses.py month --relative current --json
bash scripts/query_courses.sh month --month 2026-07 --json
```

### 上游响应结构

接口成功时返回一个 JSON 对象，key 为中文月份标签，value 为对应月份的课程数组。

| 字段 | 类型 | 说明 | 示例 |
|------|------|------|------|
| `1月` / `2月` / `...` / `12月` | array | 对应月份的课程列表 | `[{...}]` |

月份数组中的课程对象字段如下：

| 字段 | 类型 | 说明 | 示例 |
|------|------|------|------|
| `title` | string | 课程标题 | `"新建一个课程7月开始"` |
| `url` | string | 课程详情链接 | `"https://m.ebrun.com/app/demand.html?id=1913&type=3"` |
| `status` | string | 课程状态；部分数据可能为空字符串 | `"报名中"` |
| `date` | string | 课程时间文案 | `"07月08日"` |
| `city` | string | 课程地点 | `"线上"` |

### 完整响应示例

```json
{
  "7月": [
    {
      "title": "新建一个课程7月开始",
      "url": "https://m.ebrun.com/app/demand.html?id=1913&type=3",
      "status": "",
      "date": "07月08日",
      "city": "线上"
    },
    {
      "title": "再次新建一个本月报名的额",
      "url": "https://m.ebrun.com/app/demand.html?id=1914&type=3",
      "status": "报名中",
      "date": "07月07日",
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

### 脚本标准化输出

`python3 scripts/query_courses.py month --month 2026-07 --json` 与 `bash scripts/query_courses.sh month --month 2026-07 --json` 不会原样返回整个上游对象，而是会先提取目标月份，再输出一个带元信息的对象：

| 字段 | 类型 | 说明 |
|------|------|------|
| `requested_month` | string | 用户传入的月份 |
| `resolved_month` | string | 实际用于查询的月份；非法月份时会回退到当前月份 |
| `month_input_valid` | boolean | 用户输入是否为合法 `YYYY-MM` |
| `notice` | string | 非法月份时的回退提示；合法输入时为空字符串 |
| `courses` | array | 目标月份的标准化课程数组 |

`courses` 数组中的每一项会被标准化为：

| 输出字段 | 说明 |
|------|------|
| `title` | 标题；缺失时填 `未注明` |
| `url` | 原始链接文本 |
| `status` | 状态；为空时填 `状态待更新`；原始值为 `立即报名` 时统一映射为 `正在报名` |
| `date_text` | 优先读取 `date_text`，否则回退到 `date` |
| `city` | 地点；缺失时填 `未注明` |
| `summary` | 摘要；当前课程接口通常没有该字段，脚本会填 `未注明` |
| `month` | 当前查询月份，例如 `2026-07` |
| `tags` | 标签数组会转成逗号分隔字符串；缺失时为空字符串 |

### 标准化输出示例

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

## 月份解析规则

脚本内部按 `YYYY-MM` 形式接收月份参数，再映射成上游接口中的中文月份标签。

```text
2026-01 -> 1月
2026-07 -> 7月
2026-12 -> 12月
```

支持两种月份输入方式：

1. `--month YYYY-MM`
2. `--relative current|next`

如果 `--month` 不合法，脚本会自动回退到当前月份，并在返回结果里通过 `month_input_valid=false` 和 `notice` 说明。

## 错误处理

| 场景 | 说明 | 处理建议 |
|------|------|----------|
| `200` | 成功返回 JSON | 正常解析 |
| `403` | 访问被拒绝 | 检查请求来源、请求头或站点策略变化 |
| `404` | JSON 资源不存在 | 检查配置中的接口地址是否正确 |
| `429` / `500` / `502` / `503` / `504` | 服务暂时不可用或被限流 | 等待后重试，建议最多 3 次 |
| 网络超时 | 请求超时或连接失败 | 稍后重试 |
| JSON 解析失败 | 返回内容不是合法 JSON | 视为接口格式异常，停止继续解析 |
| 近期接口顶层不是数组 | 接口格式变更 | 视为接口格式异常，停止继续解析 |
| 月份接口顶层不是对象 | 接口格式变更 | 视为接口格式异常，停止继续解析 |
| 指定月份不是数组 | 接口格式变更 | 视为接口格式异常，停止继续解析 |

## 防御性处理说明

优先直接使用 Skill 自带脚本，而不是在运行时重写请求逻辑。

```bash
python3 scripts/query_courses.py recent --json
python3 scripts/query_courses.py month --month 2026-07 --json
```

脚本当前已内置以下处理：

1. 域名白名单校验，仅允许请求 `www.ebrun.com` 和 `api.ebrun.com`
2. 参数校验，禁止非法月份格式和非法相对月份参数
3. HTTP 状态码分类处理，对 `403`、`404`、`503` 等返回明确错误
4. 对 `429`、`500`、`502`、`503`、`504` 和超时场景做有限重试
5. JSON 结构校验，要求近期接口顶层必须为数组，月份接口顶层必须为对象
6. 统一字段标准化，对缺失的 `status`、`city`、`summary`、`date_text` 做默认填充

## 数据来源说明

这两个接口都来自亿邦动力站点的课程 JSON 文件。Skill 不直接抓取网页 HTML，而是优先读取这些 JSON 资源，以降低解析复杂度并提升稳定性。

其中：

1. `ebs_course_all.json` 适合做“最近有什么课”查询
2. `ebs_course_year.json` 适合做“某个月课程表”查询

## 版本检查接口

### 接口基础信息

| 属性 | 值 |
|------|----|
| URL | `https://www.ebrun.com/_index/ClaudeCode/SkillJson/skill_version.json` |
| 方法 | `GET` |
| 认证 | 无需认证 |
| 响应格式 | `application/json` |
| 顶层结构 | `object` |
| 当前关心字段 | `ebrun-mts-course` |

### 请求示例

```http
GET https://www.ebrun.com/_index/ClaudeCode/SkillJson/skill_version.json
```

### 响应结构

接口成功时返回一个 JSON 对象，key 为 skill 名称，value 为对应的远端版本号。

| 字段 | 类型 | 说明 | 示例 |
|------|------|------|------|
| `ebrun-mts-course` | string | 当前 skill 的远端版本号 | `"1.0.0"` |

### 响应示例

```json
{
  "ebrun-mts-course": "1.0.0"
}
```

## 版本比较规则

版本检查时，实际比较规则如下：

1. 优先请求版本接口，读取 `ebrun-mts-course` 字段
2. 读取本地 `references/config.json` 中的 `_meta.version`
3. 将远端接口版本号与本地 `_meta.version` 做比对
4. 如果两者不一致，则提示更新

## 检查频率控制

本地 `references/config.json` 中的 `check_interval_hours` 用于控制最短检查间隔，避免每次调用都访问远端。运行时缓存单独写入临时缓存文件，不回写 `references/config.json`。

| 字段 | 类型 | 说明 |
|------|------|------|
| `check_interval_hours` | number | 最短检查间隔，单位为小时 |
| `last_check_time` | int | 上次成功获取远端版本信息的 Unix 时间戳（秒） |
| `last_known_version` | string | 上次成功检查到的远端版本号 |
| `last_check_source` | string | 上次成功检查的来源，如 `remote_api`、`github_config_json` |
| `last_update_available` | boolean | 上次检查时是否检测到更新 |
| `last_version_file_url` | string | 上次降级到远端仓库版本文件时使用的实际地址 |

### 频率控制规则

1. 如果当前时间距离 `last_check_time` 未超过 `check_interval_hours`
2. 且本地已有 `last_known_version`、`last_check_source` 等缓存字段
3. 则默认直接返回缓存结果，不再联网请求
4. 此时脚本返回的 `status` 为 `cached`
5. 如需忽略间隔限制，可使用 `--force` 强制执行远端检查
6. 如果显式传入自定义 `--version-url`，只会复用同一版本接口地址对应的缓存结果

## 版本接口失败时的降级策略

如果版本接口请求失败，脚本会继续执行以下降级流程：

1. 读取本地 `references/config.json` 中的 `update_url_github` 和 `update_url_gitee`
2. 从仓库地址推导远端 `references/config.json` 地址
3. 优先读取远端仓库中的 `_meta.version`
4. 将远端仓库中的 `_meta.version` 与本地 `_meta.version` 做比对
5. 如果版本接口和远端仓库版本文件都失败，才返回“当前无法判断是否有更新”

### 远端仓库版本文件地址推导规则

#### GitHub

由仓库地址：

```text
https://github.com/<owner>/<repo>
```

推导候选地址：

```text
https://raw.githubusercontent.com/<owner>/<repo>/main/references/config.json
https://raw.githubusercontent.com/<owner>/<repo>/master/references/config.json
```

#### Gitee

由仓库地址：

```text
https://gitee.com/<owner>/<repo>
```

推导候选地址：

```text
https://gitee.com/<owner>/<repo>/raw/main/references/config.json
https://gitee.com/<owner>/<repo>/raw/master/references/config.json
```

## 更新脚本输出字段

`scripts/update.py` 和 `scripts/update.sh` 会输出以下关键字段：

| 字段 | 说明 |
|------|------|
| `skill_name` | skill 名称，固定为 `ebrun-mts-course` |
| `current_version` | 本地当前版本 |
| `latest_version` | 远端最新版本；无法判断时为 `unknown` |
| `update_available` | 是否有可用更新 |
| `check_source` | 检查来源：`remote_api`、`github_config_json`、`gitee_config_json` 或 `unavailable` |
| `status` | 检查状态：`ok`、`cached`、`degraded` |
| `version_api_url` | 实际使用的版本接口地址 |
| `version_file_url` | 降级到远端仓库 `references/config.json` 时使用的实际地址 |
| `update_url_github` | GitHub 更新地址 |
| `update_url_gitee` | Gitee 更新地址 |
| `message` | 本轮版本检查结果说明 |
| `remote_check_error` | 版本接口失败时的错误信息 |
| `repo_version_check_error` | 远端仓库版本文件也失败时的错误信息 |
