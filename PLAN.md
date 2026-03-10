# `edict-codex` v1 计划：Symphony 内核 + Edict 全量控制面 + Plane 任务源

## 摘要
新项目 `edict-codex` 以 **Symphony Elixir** 为主干，保留其编排、工作区、Codex app-server、重试与观测能力；移除 `Linear` 依赖，改为 **Plane 作为唯一任务真相源**；引入 **Edict 前端整体作为 v1 控制面基底**，由 **Phoenix 托管 React/Vite 构建产物**。  
v1 采用 **强隔离多会话** 架构：`皇上 → 太子 → 中书省 → 门下省 → 尚书省 → 六部 → 回奏` 中每个角色都是独立的 Codex 会话与独立运行单元，六部可并发执行。  
v1 范围为 **Edict 全量控制面**，但**不包含** `天下要闻 / 上朝仪式` 这类周边资讯产品功能。

## 关键实现
### 1. 仓库与技术栈
- 新仓库：`~/src/edict-codex`，远程为 `https://github.com/leinasi2014/edict-codex.git`
- 后端主语言：`Elixir`
- 前端主语言：`TypeScript + React + Vite`
- 部署形态：Phoenix 单服务托管 API、实时通道与 React 构建产物
- 不重写 Symphony 内核，不改为 C# / Rust / 全 TS

### 2. 任务系统：Linear → Plane
- 删除运行时对 `Linear` 的依赖，新增 `Plane.Client` 与 `Plane.Adapter`
- 通用化当前 tracker 层，保留 `Tracker` 抽象，移除 `linear_*` 作为唯一运行语义
- v1 中 Plane 作为唯一外部任务真相源，负责：
  - 项目
  - issue
  - 状态
  - 评论 / 回奏
  - 指派 / 元数据
- 后端必须支持的 Plane 能力：
  - 拉取候选 issue
  - 按状态筛 issue
  - 按 ID 回查 issue
  - 更新 issue 状态
  - 创建评论 / 回奏
  - 读取项目与基础元数据
- `WORKFLOW.md` / 配置改为 `tracker.kind: plane`，并使用 `PLANE_*` 环境变量
- v1 默认使用 Docker 自托管 Plane 作为开发/自用环境

### 3. 编排内核：帝国链真实状态机
- 在 Symphony 内核中新增真实运行时阶段，不仅是 UI 映射
- v1 角色链固定为：
  - 皇上：任务入口 / 下旨
  - 太子：任务分拣 / 任务归类 / 优先级确认
  - 中书省：规划与拆解
  - 门下省：审议与拒收/返工判定
  - 尚书省：任务派发与执行编排
  - 六部：执行节点（可并发）
  - 回奏：汇总、提交结果、回写 Plane
- 每个角色是独立 Codex 会话与独立 runtime unit
- 每个角色有明确输入/输出契约：
  - 输入：上阶段产物 + 当前 issue + workspace 上下文
  - 输出：结构化阶段结果、状态、审议意见、执行计划、最终回奏
- 六部执行采用并发子任务模型，但由尚书省统一汇总和调度
- 新内核需要引入：
  - `role`
  - `stage`
  - `parent_session_id`
  - `child_session_ids`
  - `stage_result`
  - `handoff_payload`
  - `approval_decision`
- 保留 Symphony 原有重试、工作区隔离、run attempt、恢复逻辑，但扩展到多角色会话树

### 4. 前端：Edict 全量控制面接入
- 整体复制 `edict/frontend` 进入新仓库作为前端起点
- 不直接兼容旧 Edict Python API；改由 Phoenix 新增前端专用聚合 API
- Phoenix 负责：
  - 控制面 REST API
  - 实时更新通道（Phoenix Channels / WebSocket）
  - React 构建产物托管
- v1 前端保留并打通以下控制面：
  - 旨意/任务看板
  - 省部调度总览
  - 任务流转详情
  - 模型配置
  - 技能配置
  - 官员总览
  - 会话记录
  - 奏折归档
  - 圣旨模板
- `天下要闻 / 上朝仪式` 页面与功能不进入 v1
- 前端所有数据必须来源于：
  - Symphony 运行时快照
  - Plane 任务数据
  - 新的角色/阶段执行模型
- 不保留旧 demo/dashboard 单文件方案

### 5. 后端接口与数据契约
- 现有 `/api/v1/state`、`/api/v1/:issue_identifier`、`/api/v1/refresh` 保留为底层观测 API
- 新增 Edict 控制面聚合接口，至少覆盖：
  - 任务总览 / kanban 数据
  - 任务详情 / 阶段链路
  - 角色会话列表
  - 当前活跃角色与最近动作
  - 模型配置读取/更新
  - 技能配置读取/更新
  - 奏折/归档读取
  - 模板读取/触发
  - 任务控制动作（暂停/取消/重试/推进）
- 新增实时事件流数据模型，前端可订阅：
  - 角色会话创建
  - 阶段进入/退出
  - 角色消息
  - 审议结果
  - 派发结果
  - 六部执行更新
  - 回奏完成
- 统一 issue/task 表达，不再混用 “Linear issue” 命名；外部真相源是 Plane，但内核领域对象保持通用任务语义

## 测试计划
- **Tracker 层**
  - Plane 认证、项目查询、issue 拉取、状态更新、评论写入
- **内核状态机**
  - 单任务完整走通：皇上 → 太子 → 中书 → 门下 → 尚书 → 六部 → 回奏
  - 门下省拒绝后进入 `Rework`
  - 六部并发执行与结果汇总
  - 多角色 session tree 恢复与重试
- **工作区与执行**
  - 每个角色会话使用安全工作目录
  - 失败重试不污染其他角色会话
  - Codex session 生命周期与日志关联完整
- **前端**
  - 全量控制面页面能加载并显示真实数据
  - 实时事件驱动页面刷新正常
  - 控制动作能触发后端并更新状态
- **端到端**
  - 从 Plane 新建 issue 到回奏完成全流程跑通
  - 至少一条“返工”路径和一条“六部并发执行”路径跑通

## 假设与默认决策
- v1 以 **保留 Symphony 内核能力** 为硬约束，不做全量重写
- v1 允许是双栈：Elixir 后端 + TS 前端
- `edict/frontend` 作为前端基底整体导入，样式和页面结构尽量复用
- v1 不实现 `天下要闻 / 上朝仪式` 等周边资讯功能
- Plane 为唯一外部任务真相源；不保留 Linear，也不做 Plane/内部双真相源
- Codex 多 agent 采用 **强隔离多会话**，而不是单主会话 + 子代理模拟
