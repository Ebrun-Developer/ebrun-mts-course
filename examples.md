# 使用示例集合 — 亿邦马蹄社课程

## 示例 1：自然语言触发 — 查询近期课程

**用户输入：**

```text
马蹄社最近有什么课
```

**技能行为：**

1. 识别为“最近课程查询”
2. 调用：

```bash
python3 scripts/query_courses.py recent --json
```

3. 获取近期课程数组
4. 按返回顺序逐条渲染全部课程，不做人为截断

**期望输出：**

```markdown
🎓 马蹄社近期课程
获取时间: 2026-06-08 15:00:00

[课程标题 A](https://m.ebrun.com/app/demand.html?id=1914&type=3)
时间：07/07 00:00 | 状态：正在报名
地点：线上

[课程标题 B](https://m.ebrun.com/app/demand.html?id=1913&type=3)
时间：07/08 00:00 | 状态：正在报名
地点：线上

更多资讯请见[亿邦官网](https://www.ebrun.com/)
```

---

## 示例 2：自然语言触发 — 查询指定月份课程表

**用户输入：**

```text
马蹄社7月课程表
```

**技能行为：**

1. 识别为“月份课程表查询”
2. 解析目标月份为 `2026-07`
3. 调用：

```bash
python3 scripts/query_courses.py month --month 2026-07 --json
```

4. 从脚本返回对象的 `courses` 数组中读取课程并渲染

**期望输出：**

```markdown
🗓️ 马蹄社课程表 | 2026-07
获取时间: 2026-06-08 15:05:00

[新建一个课程7月开始](https://m.ebrun.com/app/demand.html?id=1913&type=3)
时间：07月08日 | 状态：状态待更新
地点：线上

[再次新建一个本月报名的额](https://m.ebrun.com/app/demand.html?id=1914&type=3)
时间：07月07日 | 状态：报名中
地点：线上

更多资讯请见[亿邦官网](https://www.ebrun.com/)
```

---

## 示例 3：自然语言触发 — 查询当月课程

**用户输入：**

```text
马蹄社当月有什么课程
```

**技能行为：**

1. 识别为“月份课程表查询”
2. 将“当月”解析为当前月份
3. 调用：

```bash
python3 scripts/query_courses.py month --relative current --json
```

**同类表达：**

- `马蹄社当月课程安排`
- `马蹄社这个月有什么课`
- `帮我看下本月马蹄社课程`

---

## 示例 4：自然语言触发 — 查询下个月课程

**用户输入：**

```text
马蹄社下个月有什么课程
```

**技能行为：**

1. 识别为“月份课程表查询”
2. 将“下个月”解析为 `--relative next`
3. 调用：

```bash
python3 scripts/query_courses.py month --relative next --json
```

**适用场景：**

- 提前查看下个月马蹄社安排
- 在日程规划或内容同步工作流中复用

---

## 示例 5：非法月份输入时自动回退到当前月份

**用户输入：**

```text
马蹄社2026-13课程表
```

**技能行为：**

1. 用户输入的月份不符合 `YYYY-MM`
2. 自动回退到当前月份
3. 脚本返回：

```json
{
  "requested_month": "2026-13",
  "resolved_month": "2026-06",
  "month_input_valid": false,
  "notice": "你提供的月份不正确，已为你展示当前月份（2026-06）课程。",
  "courses": []
}
```

**期望输出：**

```markdown
你提供的月份不正确，已为你展示当前月份（2026-06）课程。

🗓️ 马蹄社课程表 | 2026-06
获取时间: 2026-06-08 15:10:00

...
```

---

## 示例 6：Python — 直接读取近期课程 JSON

```python
import json
import subprocess
from pathlib import Path

skill_dir = Path(".claude/skills/ebrun-mts-course")

result = subprocess.run(
    [
        "python3",
        str(skill_dir / "scripts" / "query_courses.py"),
        "recent",
        "--json",
    ],
    check=True,
    capture_output=True,
    text=True,
)

courses = json.loads(result.stdout)
for item in courses[:3]:
    print(item["title"])
    print(item["date_text"])
    print(item["url"])
    print()
```

**适用场景：**

- 在上层代理中复用课程查询能力
- 做课程标题、时间和链接的结构化处理
- 避免手写请求逻辑和 JSON 标准化逻辑

---

## 示例 7：Python — 读取月份课程表并处理 `courses`

```python
import json
import subprocess
from pathlib import Path

skill_dir = Path(".claude/skills/ebrun-mts-course")

result = subprocess.run(
    [
        "python3",
        str(skill_dir / "scripts" / "query_courses.py"),
        "month",
        "--month",
        "2026-07",
        "--json",
    ],
    check=True,
    capture_output=True,
    text=True,
)

payload = json.loads(result.stdout)
print("resolved_month =", payload["resolved_month"])

for item in payload["courses"]:
    print("-", item["title"], "|", item["date_text"], "|", item["city"])
```

**适用场景：**

- 在工作流里读取指定月份课程
- 保留 `resolved_month`、`notice` 等元信息
- 把月份课程结果继续交给别的 Agent 或格式化模块

---

## 示例 8：Shell — 直接查看文本表格

```bash
# 近期课程 ASCII 表格
python3 scripts/query_courses.py recent --table

# 指定月份课程表 ASCII 表格
python3 scripts/query_courses.py month --month 2026-07 --table

# Python 不可用时使用 Shell 版本
bash scripts/query_courses.sh month --month 2026-07 --table
```

**说明：**

- 默认输出 JSON
- 显式传 `--table` 时输出 ASCII 表格
- 月份查询支持 `--month` 和 `--relative`

---

## 示例 9：指定月份无课程

**用户输入：**

```text
马蹄社12月课程表
```

**技能行为：**

1. 识别为月份课程表查询
2. 调用目标月份查询
3. 如果返回的 `courses` 为空数组，则输出“该月份当前无已记录课程”

**期望输出：**

```markdown
🗓️ 马蹄社课程表 | 2026-12

该月份当前无已记录课程。

更多资讯请见[亿邦官网](https://www.ebrun.com/)
```

---

## 示例 10：版本检查 — 判断 skill 是否需要更新

```bash
# 常规检查
python3 scripts/update.py --json

# 忽略本地检查间隔，强制检查远端版本
python3 scripts/update.py --json --force

# 以文本方式查看结果
python3 scripts/update.py --table
```

**典型返回字段：**

- `skill_name`
- `current_version`
- `latest_version`
- `update_available`
- `check_source`
- `status`
- `message`

当 `update_available=true` 时，可在最终结果页脚追加更新提示。
