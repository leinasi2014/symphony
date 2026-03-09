```text
╭─ SYMPHONY STATUS
│ Agent 数: 1/10
│ 吞吐: 15 tps
│ 运行时长: 45分 0秒
│ 令牌: 输入 18,000 | 输出 2,200 | 总计 20,200
│ 速率限制: gpt-5 | 主限额 0/20,000 reset 95s | 次限额 0/60 reset 45s | 额度 无
│ 项目: https://linear.app/project/project/issues
│ 下次刷新: 暂无
├─ 运行中
│
│   编号       阶段             PID      时长 / 轮次...   令牌         会话             事件                                     
│   ───────────────────────────────────────────────────────────────────────────────────────────────────────────────
│ ● MT-638   retrying       4242     20分 25秒 /...     14,200 thre...567890  agent message streaming: waiting on ...
│
├─ 退避队列
│
│  ↻ MT-450 attempt=4 in 1.250s error=rate limit exhausted
│  ↻ MT-451 attempt=2 in 3.900s error=retrying after API timeout with jitter
│  ↻ MT-452 attempt=6 in 8.100s error=worker crashed restarting cleanly
│  ↻ MT-453 attempt=1 in 11.000s error=fourth queued retry should also render after removing the top-three limit
╰─
```
