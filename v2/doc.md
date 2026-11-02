# Hello!Note 数据库结构 — V2 版本说明

> 本目录（`sql/v2/`）是 V1 之后的**第一次结构迭代**，对应前端「富文本格式区分（Markdown / 纯文本）」功能所需的数据库变更。

## 一、V2 相对 V1 的变更点

| 数据表 | 变更类型 | 字段 | 类型 | 约束 | 说明 |
| --- | --- | --- | --- | --- | --- |
| `notes` | **新增列** | `format` | `VARCHAR(16)` | `NOT NULL DEFAULT 'markdown'` | 内容格式：`markdown`（需 Markdown 解析、可预览）/ `text`（纯文本，所写即所见） |

V2 **不改动** `users`、`tags`、`note_tags`、`attachments` 四张表的结构，仅对 `notes` 做增量扩展，保证与 V1 向后兼容（老数据自动归为 `markdown`，无需手动修正内容）。

## 二、为什么要加 `format` 列

第一版数据库设计里，笔记正文 `content` 一律按 Markdown 看待（编辑器的预览、语法按钮都基于该假设）。

但真实使用中存在两类内容诉求：

- **Markdown**：需要语法解析、可切换「预览」渲染（标题/列表/引用/代码等）；
- **纯文本（text）**：如粘贴的日志、代码片段、对话记录等，所写即所见，**不应被当成 Markdown 解析**，预览与语法按钮也应禁用。

因此需要在数据层持久化每篇笔记的内容格式，使「格式区分」在刷新、跨设备、API 消费方之间保持一致。该字段已贯穿：

- 后端：`Note` 模型 → `NoteOut / NoteCreate / NoteUpdate` Schema → `NoteRepository` → `NoteService` → API；
- 前端：`NoteFormat` 类型 → API 映射 → 编辑器工具栏「MD / TXT」切换与预览禁用 → 列表/详情/导入按格式处理。

## 三、完整 SQL 与迁移脚本位置

| 文件 | 作用 |
| --- | --- |
| `sql/v2/sql_v2.sql` | V2 完整建表 SQL（从零初始化用）＋ V1→V2 **幂等迁移脚本**（已存在库上执行，重复运行安全） |

### 3.1 已有 V1 库升级（推荐，最小变更）

直接执行 `sql_v2.sql` 中「第一部分：V1 → V2 升级」即可。其核心为：

```sql
USE hello_note;

ALTER TABLE notes
  ADD COLUMN format VARCHAR(16) NOT NULL DEFAULT 'markdown'
  COMMENT '内容格式：markdown 需解析可预览 / text 纯文本';
```

脚本已用 `information_schema` 判定列是否存在，重复执行不会报错。存量笔记的 `format` 会被 `DEFAULT 'markdown'` 自动回填。

### 3.2 从零初始化 V2 库

执行 `sql_v2.sql` 中「第二部分：V2 完整建表 SQL」（注意先 `CREATE DATABASE hello_note`，且库为空时再执行，避免 `table exists`）。该段包含全部五张表（`users`、`notes`、`tags`、`note_tags`、`attachments`），其中 `notes` 已含 `format` 列。

## 四、联调修复说明

本次 `notes` 表缺少 `format` 列，而 ORM `Note` 模型已声明该列，导致后端所有涉及 `notes` 的查询（如仪表盘「最近笔记」、笔记列表/详情）在执行 `SELECT ... notes.format ...` 时抛出 `Unknown column 'format'`，对外表现为 **HTTP 500**。连带地，失败查询会污染数据库连接池，使同一时间窗口内的其他仪表盘接口（如「标签」）也返回 500。

应用本 V2 迁移后：

1. `notes` 表具备 `format` 列，所有 `Note` 查询恢复正常；
2. 仪表盘、列表、详情、编辑器预览等接口不再 500；
3. 老数据默认 `markdown`，新笔记按用户在前端选择的格式落库。

## 五、版本约定（沿用 V1）

- 数据库：`hello_note`，MySQL 8.0+，InnoDB，utf8mb4 / utf8mb4_0900_ai_ci；
- 结构迭代统一放在仓库 `sql/` 下，按 `v1 / v2 / ...` 递增；
- 每次迭代目录内提供：`sql_vX.sql`（完整结构 + 升级脚本）与 `doc.md`（变更说明）；
- 正式环境以「迁移脚本 / Alembic」为主要变更方式，本 `sql/` 目录作为结构参考与手动初始化脚本。

## 六、V2 验收标准

- `notes` 表存在 `format` 列，类型为 `VARCHAR(16)`、`NOT NULL`、默认 `'markdown'`；
- 存量笔记 `format` 均为 `markdown`；
- 新建并保存一篇 `text` 格式笔记后，库中该笔记 `format = 'text'`；
- 仪表盘「最近笔记」「标签」「统计」接口均返回 200；
- 笔记列表 / 详情接口不再 500。
