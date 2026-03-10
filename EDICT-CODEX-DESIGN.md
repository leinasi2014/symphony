# `edict-codex` 设计文档（v1）

## 1. 文档目的

本文档用于把 `PLAN.md` 中的产品目标落成一份便于后续实现、评审和持续迭代的设计文档。

它回答 4 个问题：

1. `edict-codex` 到底是什么
2. 为什么要基于 Symphony，而不是重写
3. v1 需要实现哪些系统边界与接口
4. 先做什么、后做什么，才能以最低风险跑通第一版

---

## 2. 项目定义

`edict-codex` 是一个以 **Symphony Elixir** 为执行内核、以 **Plane** 为唯一任务真相源、以 **Edict 前端** 为控制面的多角色 AI 编排系统。

它的目标不是做一个新的“聊天式 agent 壳子”，而是做一个：

- 可编排
- 可观测
- 可审议
- 可回溯
- 可人工干预
- 可多角色并发执行

的任务执行平台。

v1 的最终形态是：

- **后端**：Elixir / Phoenix / Symphony runtime
- **前端**：TypeScript + React + Vite（基于 Edict 前端）
- **任务系统**：Plane
- **执行模型**：三省六部式多角色会话树

---

## 3. 核心产品目标

### 3.1 要保留的能力

来自 Symphony 的核心能力必须保留：

- 轮询与调度
- 工作区隔离
- Codex app-server 驱动
- retry / continuation / recovery
- 运行时观测
- 无数据库前提下的轻量恢复能力

### 3.2 要替换的能力

来自现有 Symphony 的 `Linear` 依赖必须替换为 `Plane`：

- 不再以 Linear 作为运行时事实来源
- 不保留 Plane / Linear 双写或双读
- v1 中 Plane 是唯一外部任务真相源

### 3.3 要新增的能力

v1 不是单纯换 tracker，还要新增：

- 多角色真实状态机
- 角色会话树
- 角色级运行时观测
- Edict 控制面聚合 API
- 前端控制动作与实时更新

---

## 4. v1 范围

### 4.1 纳入 v1

- Plane 任务读取与回写
- Symphony 内核运行时保留并扩展
- 三省六部多角色链路
- Edict 全量控制面主体页面
- Phoenix 托管 API + WebSocket + 前端产物
- 任务详情、阶段链路、角色活跃状态、控制动作

### 4.2 不纳入 v1

以下功能明确排除：

- `天下要闻`
- `上朝仪式`
- 旧 Edict Python backend 兼容层
- 为 v1 引入新持久化数据库作为强依赖
- 多真相源并存的混合架构

---

## 5. 总体架构

### 5.1 总体分层

`edict-codex` 采用 5 层结构：

1. **Policy Layer**
   - `WORKFLOW.md`
   - 角色 prompt 模板
   - 团队规则 / handoff 约束

2. **Config Layer**
   - `tracker.kind = plane`
   - `PLANE_*` / workspace / codex / server 配置
   - 角色链与执行策略配置

3. **Coordination Layer**
   - Orchestrator
   - 任务派发
   - 并发、重试、恢复、状态推进
   - 多角色 session tree 管理

4. **Execution Layer**
   - Workspace 管理
   - Codex session 启动
   - 角色输入输出与 handoff

5. **Control Plane Layer**
   - Phoenix REST API
   - Phoenix Channels / WebSocket
   - React 控制面

### 5.2 系统边界

#### Symphony 内核负责

- 拉取候选任务
- 调度和执行任务
- 管理角色会话与工作区
- 记录运行时状态
- 对外暴露底层 observability

#### Plane 负责

- 项目与工作项（task / issue）事实来源
- 状态定义与状态更新
- 评论 / 回奏
- 元数据读取

#### Edict 前端负责

- 看板与运营界面
- 模型配置、技能配置、官员总览
- 任务详情与阶段链路
- 控制动作触发

---

## 6. 关键设计决策

### 6.1 不重写 Symphony

决策：**基于当前 Symphony Elixir 实现扩展，而不是重写为新的后端。**

理由：

- 现有调度、工作区、retry、observability 已可复用
- 可在现有抽象上替换 tracker，不必推翻执行内核
- 降低 v1 的系统性风险

### 6.2 保留 `Tracker` 抽象

决策：**保留现有 `Tracker` 边界，新增 `Plane.Adapter` / `Plane.Client`。**

理由：

- 当前 Symphony 已有清晰 tracker 接口
- 先换 tracker，后换状态机，能把改造拆成低风险阶段

### 6.3 不兼容旧 Python 后端

决策：**Edict 前端保留，Python backend 不保留。**

理由：

- 旧 API 是 demo / 本地服务导向，不适合作为最终内核接口
- Phoenix 需要统一承担 API、实时事件和静态产物托管

### 6.4 多角色是“真实运行时”，不是 UI 投影

决策：**皇上 / 太子 / 中书 / 门下 / 尚书 / 六部 / 回奏 是运行时实体，不是前端显示标签。**

理由：

- 只有真实 runtime unit 才能支撑会话树、失败恢复、并发与审议机制
- UI 只是投影这些运行态，不反向定义它们

### 6.5 v1 先走最小纵切，不一次性铺满全部能力

决策：**第一阶段先跑通一条端到端纵切，再扩展到完整控制面与六部并发。**

理由：

- 减少同时改 tracker + runtime + frontend 带来的叠加复杂度
- 先证明“Plane -> Symphony -> Phoenix -> Edict -> 回奏”链路成立

---

## 7. 领域模型

### 7.1 任务模型

外部事实来源叫 `Plane Work Item`，但内核统一使用中性任务语义，避免运行时充满 `linear_issue` 历史命名。

建议领域对象：

- `Task`
  - `id`
  - `identifier`
  - `title`
  - `description`
  - `state`
  - `priority`
  - `labels`
  - `url`
  - `project`
  - `assignee`
  - `source_meta`

### 7.2 角色运行模型

新增角色运行对象：

- `RoleSession`
  - `session_id`
  - `task_id`
  - `role`
  - `stage`
  - `parent_session_id`
  - `child_session_ids`
  - `status`
  - `workspace_path`
  - `started_at`
  - `updated_at`
  - `last_message`
  - `token_usage`
  - `stage_result`
  - `handoff_payload`
  - `approval_decision`

### 7.3 任务编排对象

- `TaskRuntime`
  - `task_id`
  - `root_session_id`
  - `active_role`
  - `current_stage`
  - `role_sessions`
  - `retry_state`
  - `final_memorial`

---

## 8. Tracker 设计：Plane 替换 Linear

### 8.1 必需能力

`Plane.Client` v1 至少实现：

- 获取项目列表 / 元数据
- 获取可执行任务列表
- 按状态筛选任务
- 按 ID / identifier 回查任务
- 更新任务状态
- 创建评论 / 回奏
- 读取状态映射关系

### 8.2 集成方式

保留现有 `Tracker` 接口：

- `fetch_candidate_issues`
- `fetch_issues_by_states`
- `fetch_issue_states_by_ids`
- `create_comment`
- `update_issue_state`

实现策略：

- `Config.tracker_kind()` 支持 `plane`
- `Tracker.adapter()` 在 `plane` 时返回 `Plane.Adapter`
- 先兼容现有 orchestrator 的调用方式，再逐步泛化命名

### 8.3 配置约定

`WORKFLOW.md` 需要支持：

```yaml
tracker:
  kind: plane
  api_key: $PLANE_API_KEY
  workspace_slug: "..."
  project_id: "..."
  active_states:
    - Todo
    - In Progress
    - Rework
  terminal_states:
    - Done
    - Cancelled
```

同时保留：

- `workspace.root`
- `hooks`
- `agent`
- `codex`
- `server`

---

## 9. 编排设计：三省六部状态机

### 9.1 固定角色链

v1 固定链路：

1. 皇上
2. 太子
3. 中书省
4. 门下省
5. 尚书省
6. 六部（并发）
7. 回奏

### 9.2 角色职责

- **皇上**：任务入口、下旨、形成原始目标
- **太子**：任务分拣、分类、优先级确认
- **中书省**：规划、拆解、定义执行结构
- **门下省**：审议、封驳、返工判定
- **尚书省**：任务派发、依赖编排、结果汇总
- **六部**：执行型子任务节点
- **回奏**：汇总产出、形成最终评论并回写 Plane

### 9.3 返工路径

门下省可以把中书省产物打回：

- 中书 -> 门下 -> `Rework` -> 中书

### 9.4 并发路径

尚书省可将任务拆到多个六部子任务：

- 尚书 -> 户部 / 礼部 / 吏部 / 兵部 / 刑部 / 工部
- 并发完成后回到尚书省聚合

### 9.5 实现策略

不要一开始把现有 `AgentRunner` 改成巨型多态体。

建议新增一层：

- `StageExecutor`
- `RoleRunner`
- `HandoffBuilder`
- `StageResult`

由新层调用现有 Codex session 启动能力。

---

## 10. 工作区设计

### 10.1 工作区组织

建议从当前“每 issue 一个工作区”扩展成：

- 每个 task 一个根工作区
- 每个角色一个子目录或子工作区

例如：

```text
/workspaces/<task-key>/
  shared/
  emperor/
  crown-prince/
  zhongshu/
  menxia/
  shangshu/
  ministry-revenue/
  ministry-rites/
  memorial/
```

### 10.2 共享与隔离

- `shared/` 保存 task 共享上下文、阶段产物、结构化 handoff
- 各角色目录保存本角色运行痕迹
- 六部执行必须彼此隔离，避免相互污染

### 10.3 失败恢复

- 单角色失败不应污染其他角色输出
- retry 应以 `RoleSession` 为粒度，必要时升级为 `TaskRuntime` 级重试

---

## 11. Phoenix 控制面设计

### 11.1 保留的底层 API

保留现有 observability 风格底层接口：

- `GET /api/v1/state`
- `GET /api/v1/:task_identifier`
- `POST /api/v1/refresh`

这组接口继续作为底层调试接口存在。

### 11.2 新增聚合 API

新增面向 Edict 前端的聚合接口：

- `GET /api/control/tasks`
- `GET /api/control/tasks/:id`
- `GET /api/control/tasks/:id/runtime`
- `GET /api/control/roles`
- `GET /api/control/models`
- `POST /api/control/models`
- `GET /api/control/skills`
- `POST /api/control/skills`
- `GET /api/control/memorials`
- `GET /api/control/templates`
- `POST /api/control/tasks/:id/actions`

### 11.3 实时事件

v1 的实时事件至少覆盖：

- 角色会话创建
- 阶段进入
- 阶段退出
- 审议结果
- 六部执行更新
- 任务完成 / 回奏完成

---

## 12. 前端设计

### 12.1 前端来源

直接以 `edict/frontend` 为起点导入。

### 12.2 v1 页面保留

保留并打通：

- 旨意/任务看板
- 省部调度总览
- 任务详情
- 模型配置
- 技能配置
- 官员总览
- 会话记录
- 奏折归档
- 圣旨模板

### 12.3 v1 页面排除

移除或隐藏：

- `天下要闻`
- `上朝仪式`

### 12.4 接口策略

不兼容旧 Python API，改为：

- 保留 UI 结构
- 重写 `api.ts` 的数据来源
- 让数据统一来自 Phoenix BFF

---

## 13. 推荐实施顺序

### 阶段 A：仓库起步

目标：在 `edict-codex` 空仓库中建立可运行骨架。

- 拷贝 Symphony Elixir 实现作为后端起点
- 初始化 Phoenix 与基础配置
- 建立新仓库 README / WORKFLOW / Makefile / dev 启动方式

### 阶段 B：Plane 接入

目标：先把 `Linear -> Plane` 换掉。

- 新增 `Plane.Client`
- 新增 `Plane.Adapter`
- `tracker.kind` 支持 `plane`
- 使用 Plane 拉任务并回写评论

### 阶段 C：最小纵切

目标：先跑通一条简化链路。

建议首条纵切：

- Plane 取 1 个任务
- 角色只启用：皇上 -> 中书 -> 回奏
- Phoenix 输出任务列表与详情
- Edict 看板显示任务
- 最终回写 Plane comment

### 阶段 D：多角色状态机

目标：引入真实三省六部运行时。

- 太子 / 门下 / 尚书 / 六部
- 返工路径
- 六部并发
- 角色 session tree

### 阶段 E：全量控制面

目标：把 Edict 主要控制面全部接通。

- 模型配置
- 技能配置
- 会话记录
- 奏折归档
- 模板触发
- 控制动作

---

## 14. v1 验收标准

### 14.1 Tracker 层

- Plane 认证通过
- 能列出候选任务
- 能按状态筛选
- 能更新状态
- 能创建评论

### 14.2 Runtime 层

- 单任务最小链路能跑通
- 至少一条返工路径能跑通
- 至少一条六部并发路径能跑通
- 角色失败重试不污染其他角色

### 14.3 前端层

- 任务看板能显示真实 Plane + runtime 数据
- 任务详情能显示阶段链路与角色信息
- 控制动作可触发后端执行
- 实时事件能驱动页面更新

### 14.4 端到端

- 从 Plane 新建任务到最终回奏完成闭环跑通

---

## 15. 当前默认假设

- v1 不做全量重写
- v1 不保留 Linear 运行依赖
- v1 不兼容旧 Python backend
- v1 允许 Elixir + TypeScript 双栈
- v1 优先跑通最小纵切，再扩展到完整三省六部

---

## 16. 下一步建议

如果从实现角度继续推进，下一份应创建的文档建议是：

1. `edict-codex` 仓库目录结构草案
2. `Plane.Adapter` 接口与字段映射文档
3. 多角色状态机详细设计文档
4. Phoenix 聚合 API 草案
5. 前端页面与 API 对照表

