根据 Hello!Note 目前的开发进度，建议现在先建立 MySQL 基础数据库结构，暂时不引入 AI、RAG、Agent、向量数据库等后续功能。

目前已经确定的技术路线是：

- 后端：FastAPI + SQLAlchemy 2.x + Alembic
- 数据库：MySQL
- 前端：Vue 3 + TypeScript
- 前后端独立开发，通过 RESTful API 通信。

此前规划的核心数据表包括 `users`、`notes`、`tags`、`note_tags` 和 `attachments`。

我建议第一版数据库围绕这五张表设计，同时先把用户与笔记的归属关系建立起来，避免以后增加用户系统时需要大幅修改笔记表。

# 一、第一版数据库结构

基础版本 V1

## 1.1 数据库名称

```
hello_note
```

建议使用 MySQL 8.0 或兼容版本，统一采用：

- 存储引擎：InnoDB
- 字符集：utf8mb4
- 排序规则：utf8mb4_0900_ai_ci（MySQL 8.0）

## 1.2 数据表规划

| 数据表           | 中文名称    | 主要作用            |
| ------------- | ------- | --------------- |
| `users`       | 用户表     | 保存用户基本信息和登录信息   |
| `notes`       | 笔记表     | 保存笔记标题、正文和所属用户  |
| `tags`        | 标签表     | 保存用户创建的标签       |
| `note_tags`   | 笔记标签关联表 | 维护笔记与标签的多对多关系   |
| `attachments` | 附件表     | 保存笔记附件的元数据和存储位置 |

## 1.3 表关系设计

数据库关系示意

users

用户信息

`id (PK)`

notes

笔记内容

`user_id (FK)`

tags

用户标签

`user_id (FK)`

note_tags

笔记与标签的关联表

`note_id (FK) + tag_id (FK)`

attachments

笔记附件，直接关联 notes

`note_id (FK)`

users 与 notes、tags 是一对多；notes 与 tags 是多对多；notes 与 attachments 是一对多。

注意：`note_tags` 是中间关联表，不直接保存笔记正文或标签名称。

# 二、数据库表字段设计

## 2.1 users 用户表

保存用户基本信息和登录凭证。

| 字段            | 类型              | 约束              | 说明       |
| ------------- | --------------- | --------------- | -------- |
| id            | BIGINT UNSIGNED | PK              | 用户 ID    |
| email         | VARCHAR(255)    | UNIQUE、NOT NULL | 登录邮箱     |
| password_hash | VARCHAR(255)    | NOT NULL        | 加密后的密码哈希 |
| display_name  | VARCHAR(100)    | NOT NULL        | 用户显示名称   |
| avatar_url    | VARCHAR(500)    | NULL            | 头像地址     |
| is_active     | BOOLEAN         | NOT NULL        | 用户是否启用   |
| created_at    | DATETIME        | NOT NULL        | 创建时间     |
| updated_at    | DATETIME        | NOT NULL        | 更新时间     |

注意：数据库只保存密码哈希，不能保存用户的明文密码。

## 2.2 notes 笔记表

这是整个项目最重要的业务表。

| 字段         | 类型              | 约束          | 说明    |
| ---------- | --------------- | ----------- | ----- |
| id         | BIGINT UNSIGNED | PK          | 笔记 ID |
| user_id    | BIGINT UNSIGNED | FK、NOT NULL | 所属用户  |
| title      | VARCHAR(255)    | NOT NULL    | 笔记标题  |
| content    | LONGTEXT        | NOT NULL    | 笔记正文  |
| is_pinned  | BOOLEAN         | NOT NULL    | 是否置顶  |
| created_at | DATETIME        | NOT NULL    | 创建时间  |
| updated_at | DATETIME        | NOT NULL    | 更新时间  |

说明：

- `user_id` 用于区分笔记属于哪个用户。
- `content` 使用 `LONGTEXT`，为以后较长的 Markdown 笔记留出空间。
- `is_pinned` 用于实现笔记置顶。
- 暂时不加入复杂的版本管理、回收站和协作功能。

## 2.3 tags 标签表

保存用户创建的标签。

| 字段         | 类型              | 约束          | 说明     |
| ---------- | --------------- | ----------- | ------ |
| id         | BIGINT UNSIGNED | PK          | 标签 ID  |
| user_id    | BIGINT UNSIGNED | FK、NOT NULL | 标签所属用户 |
| name       | VARCHAR(50)     | NOT NULL    | 标签名称   |
| color      | VARCHAR(20)     | NULL        | 标签显示颜色 |
| created_at | DATETIME        | NOT NULL    | 创建时间   |

建议增加唯一约束：

```
UNIQUE KEY uk_tags_user_name (user_id, name)
```

这样同一个用户不能创建两个完全同名的标签，但不同用户可以使用相同的标签名称。

## 2.4 note_tags 笔记标签关联表

一篇笔记可以有多个标签，一个标签也可以被多篇笔记使用。

因此需要多对多关联表。

| 字段      | 类型              | 约束    | 说明    |
| ------- | --------------- | ----- | ----- |
| note_id | BIGINT UNSIGNED | PK、FK | 笔记 ID |
| tag_id  | BIGINT UNSIGNED | PK、FK | 标签 ID |

这里使用联合主键：

```
PRIMARY KEY (note_id, tag_id)
```

避免同一篇笔记重复关联同一个标签。

## 2.5 attachments 附件表

保存附件的基本信息。

| 字段                | 类型              | 约束          | 说明         |
| ----------------- | --------------- | ----------- | ---------- |
| id                | BIGINT UNSIGNED | PK          | 附件 ID      |
| note_id           | BIGINT UNSIGNED | FK、NOT NULL | 所属笔记       |
| original_filename | VARCHAR(255)    | NOT NULL    | 原始文件名      |
| storage_key       | VARCHAR(500)    | NOT NULL    | 文件存储标识     |
| storage_provider  | VARCHAR(30)     | NOT NULL    | 存储方式       |
| mime_type         | VARCHAR(100)    | NULL        | 文件 MIME 类型 |
| size_bytes        | BIGINT UNSIGNED | NOT NULL    | 文件大小（字节）   |
| created_at        | DATETIME        | NOT NULL    | 上传时间       |

`storage_provider` 初期可以使用：

- `local`：本地文件存储。
- `s3`：S3 兼容对象存储。

这里保存的是文件元数据，不直接把文件二进制内容存入 MySQL。

# 三、完整 MySQL 建表 SQL

建议在后端仓库中建立：

```
HelloNote-Backend/
└── scripts/
    └── sql/
        └── init.sql
```

下面是第一版完整 SQL，可以作为数据库初始化脚本。

```sql

-- ==========================================
-- Hello!Note Database Initialization
-- Version: V1
-- Database: hello_note
-- MySQL: 8.0+
-- ==========================================

CREATE DATABASE IF NOT EXISTS hello_note
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_0900_ai_ci;

USE hello_note;


-- ==========================================
-- 1. users
-- 用户表
-- ==========================================

CREATE TABLE users (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,

    email VARCHAR(255) NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    display_name VARCHAR(100) NOT NULL,
    avatar_url VARCHAR(500) NULL,

    is_active BOOLEAN NOT NULL DEFAULT TRUE,

    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
        ON UPDATE CURRENT_TIMESTAMP,

    UNIQUE KEY uk_users_email (email)
) ENGINE=InnoDB
  DEFAULT CHARSET=utf8mb4
  COLLATE=utf8mb4_0900_ai_ci;


-- ==========================================
-- 2. notes
-- 笔记表
-- ==========================================

CREATE TABLE notes (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,

    user_id BIGINT UNSIGNED NOT NULL,

    title VARCHAR(255) NOT NULL,
    content LONGTEXT NOT NULL,

    is_pinned BOOLEAN NOT NULL DEFAULT FALSE,

    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
        ON UPDATE CURRENT_TIMESTAMP,

    KEY idx_notes_user_id (user_id),
    KEY idx_notes_created_at (created_at),

    CONSTRAINT fk_notes_users
        FOREIGN KEY (user_id)
        REFERENCES users(id)
        ON DELETE CASCADE
) ENGINE=InnoDB
  DEFAULT CHARSET=utf8mb4
  COLLATE=utf8mb4_0900_ai_ci;


-- ==========================================
-- 3. tags
-- 标签表
-- ==========================================

CREATE TABLE tags (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,

    user_id BIGINT UNSIGNED NOT NULL,

    name VARCHAR(50) NOT NULL,
    color VARCHAR(20) NULL,

    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

    UNIQUE KEY uk_tags_user_name (user_id, name),
    KEY idx_tags_user_id (user_id),

    CONSTRAINT fk_tags_users
        FOREIGN KEY (user_id)
        REFERENCES users(id)
        ON DELETE CASCADE
) ENGINE=InnoDB
  DEFAULT CHARSET=utf8mb4
  COLLATE=utf8mb4_0900_ai_ci;


-- ==========================================
-- 4. note_tags
-- 笔记标签关联表
-- ==========================================

CREATE TABLE note_tags (
    note_id BIGINT UNSIGNED NOT NULL,
    tag_id BIGINT UNSIGNED NOT NULL,

    PRIMARY KEY (note_id, tag_id),

    KEY idx_note_tags_tag_id (tag_id),

    CONSTRAINT fk_note_tags_notes
        FOREIGN KEY (note_id)
        REFERENCES notes(id)
        ON DELETE CASCADE,

    CONSTRAINT fk_note_tags_tags
        FOREIGN KEY (tag_id)
        REFERENCES tags(id)
        ON DELETE CASCADE
) ENGINE=InnoDB
  DEFAULT CHARSET=utf8mb4
  COLLATE=utf8mb4_0900_ai_ci;


-- ==========================================
-- 5. attachments
-- 附件表
-- ==========================================

CREATE TABLE attachments (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,

    note_id BIGINT UNSIGNED NOT NULL,

    original_filename VARCHAR(255) NOT NULL,
    storage_key VARCHAR(500) NOT NULL,
    storage_provider VARCHAR(30) NOT NULL DEFAULT 'local',

    mime_type VARCHAR(100) NULL,
    size_bytes BIGINT UNSIGNED NOT NULL,

    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

    UNIQUE KEY uk_attachments_storage_key (storage_key),
    KEY idx_attachments_note_id (note_id),

    CONSTRAINT fk_attachments_notes
        FOREIGN KEY (note_id)
        REFERENCES notes(id)
        ON DELETE CASCADE
) ENGINE=InnoDB
  DEFAULT CHARSET=utf8mb4
  COLLATE=utf8mb4_0900_ai_ci;


-- ==========================================
-- Initialization completed
-- ==========================================

```

# 四、数据库设计中的几个重要决定

这里需要提前明确一些设计原则，避免后续开发出现结构混乱。

### 4.1 为什么笔记需要 user_id？

虽然初期可能只有你自己使用，但 Hello!Note 已经规划了用户注册和登录功能。

例如：

```
用户 A
  ├── 笔记 1
  ├── 笔记 2
  └── 笔记 3

用户 B
  ├── 笔记 4
  └── 笔记 5
```

因此每篇笔记都需要关联所属用户。

后端查询笔记时，也必须根据当前登录用户进行数据权限过滤，不能仅凭 `note_id` 查询后就直接返回数据。

### 4.2 为什么不单独建立 categories 分类表？

第一版先使用标签功能即可。

标签已经能够满足：

- 技术学习
- 日常记录
- Linux
- Python
- AI
- 项目开发

未来如果需要文件夹、层级分类、独立分类管理，再增加 `categories` 表。

### 4.3 为什么附件只保存文件信息？

实际文件可以存放在：

```
本地文件系统
    ↓
S3 兼容对象存储
    ↓
其他云存储服务
```

数据库只记录文件名、存储位置、类型和大小。

这样以后从本地存储切换到云对象存储，不需要改变笔记表的设计。

注意：数据库删除附件记录并不等于实际文件已经删除，后续需要由文件服务负责清理存储对象。

### 4.4 为什么暂时不设计 AI 和 RAG 数据表？

目前核心任务是完成笔记系统。

后续可以独立增加：

```
ai_conversations
ai_messages
note_embeddings
knowledge_bases
knowledge_documents
document_chunks
agent_tasks
```

这些表应该在对应功能真正开始开发时再设计，避免提前增加暂时用不到的复杂结构。

# 五、后端项目中的数据库文件组织

建议采用 SQLAlchemy 2.x + Alembic 管理数据库结构。

最终组织形式：

```
HelloNote-Backend/
├── app/
│   ├── db/
│   │   ├── database.py
│   │   ├── session.py
│   │   └── base.py
│   │
│   └── models/
│       ├── __init__.py
│       ├── user.py
│       ├── note.py
│       ├── tag.py
│       └── attachment.py
│
├── migrations/
│   └── versions/
│
├── scripts/
│   └── sql/
│       └── init.sql
│
├── alembic.ini
└── pyproject.toml
```

其中：

| 文件              | 职责                |
| --------------- | ----------------- |
| `database.py`   | 创建数据库 Engine      |
| `session.py`    | 管理数据库 Session     |
| `base.py`       | 声明 ORM 基类、模型注册基础  |
| `user.py`       | 用户模型              |
| `note.py`       | 笔记模型              |
| `tag.py`        | 标签模型及关联模型         |
| `attachment.py` | 附件模型              |
| `migrations/`   | 保存数据库结构迁移记录       |
| `init.sql`      | 初始 SQL 参考和手动初始化脚本 |

重要： `init.sql` 适合手动初始化和理解表结构。正式开发中建议以 Alembic 迁移记录作为数据库结构变更的主要管理方式，不要长期同时通过 SQL 脚本和 ORM 手动修改同一套数据库结构。

# 六、建议的实际开发顺序

不要一次性开发所有数据库相关功能。建议按照下面的顺序进行：

1. 创建 MySQL 数据库

   创建 `hello_note`，运行初始 SQL，检查五张表是否正常生成。
2. 创建 SQLAlchemy 模型

   将五张表对应为 Python ORM 模型，定义字段、主外键和关系。
3. 配置数据库连接

   在 `.env` 中配置数据库连接字符串，通过 FastAPI 依赖注入获取 Session。
4. 接入 Alembic

   完成迁移初始化，确保后续数据库变更可以追踪和回滚。
5. 编写基础 Repository

   先实现用户、笔记、标签和附件的基本数据访问操作。
6. 开始开发笔记 CRUD API

   完成创建、查询、修改、删除笔记，再逐步接入用户认证和标签功能。

# 七、第一版数据库验收标准

- MySQL 中成功创建 `hello_note` 数据库。
- 成功创建五张基础表。
- 所有表均使用 InnoDB 和 utf8mb4。
- 主键和外键关系正常。
- 用户邮箱具有唯一约束。
- 同一个用户不能创建重复标签。
- 一篇笔记可以关联多个标签。
- 一篇笔记可以关联多个附件。
- 删除笔记时，其关联记录能够正确处理。
- 不同用户的数据能够通过 `user_id` 区分。

下一步建议：先不要急着开发 API。先把这五张表转换成 SQLAlchemy 2.x 模型，并接入 Alembic。 这样数据库结构就正式进入 Python 后端项目管理，而不是仅仅停留在一份 SQL 文件中。