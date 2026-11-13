# Hello!Note 数据库结构 — V3 版本说明

> 本目录（`sql/v3/`）是 V2 之后的**第二次结构迭代**，对应前端「面板升级」：
> 新增 **日历 / GitHub 风格活跃度热力图 / 活动时长统计** 所需的数据库变更。

## 一、V3 相对 V2 的变更点

| 数据表 | 变更类型 | 说明 |
| --- | --- | --- |
| `user_activity` | **新增表** | 用户每日活跃度记录（按 `user_id + stat_date` 唯一），累计当日笔记 增/改/删 次数与活跃时长 |

V3 **不改动** `users` / `notes` / `tags` / `note_tags` / `attachments` 五张表，仅新增一张表，完全向后兼容。

### `user_activity` 字段

| 字段 | 类型 | 约束 | 说明 |
| --- | --- | --- | --- |
| `id` | `BIGINT UNSIGNED` | PK, AUTO_INCREMENT | 主键 |
| `user_id` | `BIGINT UNSIGNED` | NOT NULL, FK→`users(id)` ON DELETE CASCADE | 所属用户 |
| `stat_date` | `DATE` | NOT NULL | 业务日（后端统一按 `Asia/Shanghai` 计算） |
| `notes_created` | `INT UNSIGNED` | NOT NULL DEFAULT 0 | 当日新增笔记次数 |
| `notes_updated` | `INT UNSIGNED` | NOT NULL DEFAULT 0 | 当日修改笔记次数（含置顶切换 `pin`） |
| `notes_deleted` | `INT UNSIGNED` | NOT NULL DEFAULT 0 | 当日删除笔记次数 |
| `active_seconds` | `INT UNSIGNED` | NOT NULL DEFAULT 0 | 当日应用内活跃时长（秒，前端心跳上报累加） |
| `created_at` / `updated_at` | `DATETIME` | 默认当前时间戳 | 行创建 / 更新时间 |

约束：
- `UNIQUE KEY uk_user_activity_user_date (user_id, stat_date)` —— 保证「一人一天一行」，是并发原子累加（`INSERT ... ON DUPLICATE KEY UPDATE`）的落点；
- `KEY idx_user_activity_date (stat_date)` —— 便于按日期范围检索。

## 二、为什么要新增这张表

V1/V2 的 `notes` 有两个限制，导致新功能无法靠「实时聚合」实现：

1. **硬删除 + 状态覆盖**：`delete` 是物理删除，`updated_at` 每次修改都被覆盖。因此**无法反推**「历史某日发生过几次修改 / 删除」——而热力图正是要按天还原这些操作次数。
2. **没有时长来源**：`notes` 完全不记录用户在应用里停留了多久，「活动时长」无从计算。

因此采用「**写时埋点、按日累加**」：在笔记增/改/删发生时，于同一事务内对 `user_activity` 做一次原子累加；前端心跳周期性上报活跃秒数，同样累加到当日行。查询侧只需按日期范围捞取稀疏行，开销极小。

**活跃点数（热力图色深）** = `notes_created + notes_updated + notes_deleted`（前端计算）。

## 三、完整 SQL 与迁移脚本位置

| 文件 | 作用 |
| --- | --- |
| `sql/v3/sql_v3.sql` | V2→V3 **幂等升级脚本**（建表 + 历史回填）＋ V3 完整建表 SQL（注释参考） |

### 3.1 已有 V2 库升级（推荐）

直接在 `hello_note` 库上执行 `sql_v3.sql` 的「第一部分」即可，核心为：

```sql
CREATE TABLE IF NOT EXISTS user_activity ( ... );   -- 幂等建表
INSERT IGNORE INTO user_activity (...)              -- 存量笔记按创建日回填
SELECT user_id, DATE(created_at), COUNT(*), 0,0,0, NOW(), NOW()
FROM notes GROUP BY user_id, DATE(created_at);
```

- `CREATE TABLE IF NOT EXISTS`：`user_activity` 是整表新增，重复执行不会报错；
- `INSERT IGNORE ... SELECT`：把已有笔记按创建日点亮热力图；若某日已有实时埋点行则跳过，重复执行不会叠加。

> ⚠️ 回填只能还原「新增」；历史「修改 / 删除 / 时长」在 V2 中未被记录，保持 0，属预期行为。
> 从升级完成起，后续所有增/改/删/时长都会真实累计。

### 3.2 从零初始化 V3 库

依次执行：`sql/v1/sql_v1.sql` → `sql/v2/sql_v2.sql`（V1→V2 升级段）→ `sql/v3/sql_v3.sql`（第一部分）。

## 四、时区口径

- 现有 `notes.created_at/updated_at` 是 `DATETIME`（naive），由 MySQL `NOW()` 生成，取服务器本地时区；
- V3 的 `stat_date` 由**后端**统一按 `Asia/Shanghai`（可在后端 `ACTIVITY_TIMEZONE` 配置）计算业务日，写入 `DATE`，**不带时分秒、不带时区偏移**；
- 前端所有日历 / 热力图按 `YYYY-MM-DD` **字符串**索引，不 `new Date()` 解析，避免跨时区漂移；
- 历史回服用 `DATE(created_at)`，与服务器本地时区一致（默认部署为国内时区，与 `Asia/Shanghai` 对齐）。

## 五、后端 / 前端落地对照

| 层 | 变更 |
| --- | --- |
| 模型 | 新增 `app/models/activity.py` (`UserActivity`)，在 `app/models/__init__.py` 注册 |
| Schema | 新增 `app/schemas/activity.py` (`ActivityDayOut` / `ActivitySummary` / `ActivityRangeOut` / `HeartbeatIn`) |
| 仓储 | 新增 `app/repositories/activity_repository.py`（`add` 原子累加、不 commit；`list_all`） |
| 服务 | 新增 `app/services/activity_service.py`（`record_heartbeat` / `get_range` 汇总） |
| 埋点 | `NoteRepository.create/update/delete` 在 `commit()` **前**用同一 `Session` 累加（覆盖含 `pin` 的全部写路径，事务原子） |
| 接口 | 新增 `GET /api/v1/activity/range?days=371`、`POST /api/v1/activity/heartbeat`（均需登录），注册进 `api_router` |
| 前端 | `dashboard.api/types/store` 扩展活跃度数据；全局 `useActivityTracker` 心跳计时；新增日历 / 热力图 / 活动时长三块面板 |

**事务一致性**：`NoteRepository` 的写方法原本各自 `commit()`。埋点调用 `ActivityRepository.add()`（只 `db.execute`、不提交），紧接在同一 `commit()` 之前，保证「笔记写入」与「活跃度累加」落在**同一事务**，不会出现笔记成功但活跃度丢失。

**启动自愈**：后端 `lifespan` 用 `UserActivity.__table__.create(checkfirst=True)` 幂等创建该新表（仅建新表、绝不改动既有表/数据）。这是防御性兜底——即使尚未执行迁移脚本，笔记增/改/删的埋点也不会因「缺表」而拖累主业务；结构规范化与历史回填仍以 `sql_v3.sql` 为准。

## 六、版本约定（沿用 V1/V2）

- 数据库：`hello_note`，MySQL 8.0+，InnoDB，utf8mb4 / utf8mb4_0900_ai_ci；
- 结构迭代统一放在仓库 `sql/` 下，按 `v1 / v2 / v3 / ...` 递增；
- 每次迭代目录内提供：`sql_vX.sql`（升级脚本 + 完整结构）与 `doc.md`（变更说明）；
- 正式环境以「迁移脚本 / Alembic」为主要变更方式，本 `sql/` 目录作为结构参考与手动初始化脚本。

## 七、V3 验收标准

- `user_activity` 表存在，`(user_id, stat_date)` 唯一；
- 执行回填后，存量笔记的创建日在热力图上有点；
- 新建 / 编辑 / 置顶 / 删除一篇笔记，当日 `notes_created/updated/deleted` 对应 +1；
- 前端停留在应用内，`active_seconds` 按心跳累加；
- `GET /activity/range` 返回 200 且 `days` / `summary` 结构正确；仪表盘原有 `stats/recent/tags` 接口不受影响。
