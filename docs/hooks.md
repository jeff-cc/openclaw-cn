---
summary: "Hooks：针对命令和生命周期事件的事件驱动自动化"
read_when:
  - 你需要针对 /new、/reset、/stop 和 Agent 生命周期事件进行事件驱动的自动化
  - 你想构建、安装或调试 Hooks
---

# Hooks

Hooks 提供了一个可扩展的事件驱动系统，用于响应 Agent 命令和事件并自动化执行操作。Hooks 会从目录中自动发现，并可以通过 CLI 命令进行管理，这与 openclaw-cn 中技能（Skills）的工作方式类似。

## 快速了解

Hooks 是当某些事情发生时运行的小型脚本。主要有两种类型：

- **Hooks**（本页）：在网关（Gateway）内部运行，当 Agent 事件触发时执行，例如 `/new`、`/reset`、`/stop` 或生命周期事件。
- **Webhooks**：外部 HTTP Webhooks，允许其他系统在 openclaw-cn 中触发工作。请参阅 [Webhook Hooks](/automation/webhook) 或使用 `openclaw-cn webhooks` 查看 Gmail 助手命令。

Hooks 也可以打包在插件中；请参阅 [插件](/plugin#plugin-hooks)。

常见用途：

- 重置会话时保存记忆快照
- 保留所有命令的审计跟踪以用于故障排除或合规性检查
- 在会话开始或结束时触发后续自动化流程
- 当事件触发时，将文件写入 Agent 工作区或调用外部 API

如果你能写一个小的 TypeScript 函数，你就能写一个 Hook。Hooks 会被自动发现，你通过 CLI 启用或禁用它们。

## 概览

Hooks 系统允许你：

- 当发出 `/new` 命令时，将会话上下文保存到记忆中
- 记录所有命令以进行审计
- 在 Agent 生命周期事件上触发自定义自动化
- 在不修改核心代码的情况下扩展 openclaw-cn 的行为

## 入门指南

### 内置 Hooks (Bundled Hooks)

openclaw-cn 附带了四个自动发现的内置 Hooks：

- **💾 session-memory**：当你发出 `/new` 时，将会话上下文保存到你的 Agent 工作区（默认为 `~/clawwork/memory/`）
- **📝 command-logger**：将所有命令事件记录到 `~/.openclaw/logs/commands.log`
- **🚀 boot-md**：当网关启动时运行 `BOOT.md`（需要启用内部 Hooks）
- **😈 soul-evil**：在清理窗口期间或随机情况下，将注入的 `SOUL.md` 内容替换为 `SOUL_EVIL.md`

列出可用的 Hooks：

```bash
openclaw-cn hooks list
```

启用一个 Hook：

```bash
openclaw-cn hooks enable session-memory
```

检查 Hook 状态：

```bash
openclaw-cn hooks check
```

获取详细信息：

```bash
openclaw-cn hooks info session-memory
```

### 入门引导

在入门引导（`openclaw-cn onboard`）期间，系统会提示你启用推荐的 Hooks。向导会自动发现符合条件的 Hooks 并将其呈现以供选择。

## Hook 发现机制

Hooks 会从三个目录（按优先级顺序）自动发现：

1. **工作区 Hooks**：`<workspace>/hooks/`（每个 Agent 独立，优先级最高）
2. **托管 Hooks**：`~/.openclaw/hooks/`（用户安装，跨工作区共享）
3. **内置 Hooks**：`<clawdbot>/dist/hooks/bundled/`（随 openclaw-cn 发布）

托管 Hook 目录可以是**单个 Hook**，也可以是**Hook 包**（包目录）。

每个 Hook 是一个包含以下内容的目录：

```
my-hook/
├── HOOK.md          # 元数据 + 文档
└── handler.ts       # 处理程序实现
```

## Hook 包 (npm/archives)

Hook 包是标准的 npm 包，通过 `package.json` 中的 `openclaw.hooks` 导出一个或多个 Hooks。安装方式如下：

```bash
openclaw-cn hooks install <path-or-spec>
```

`package.json` 示例：

```json
{
  "name": "@acme/my-hooks",
  "version": "0.1.0",
  "openclaw": {
    "hooks": ["./hooks/my-hook", "./hooks/other-hook"]
  }
}
```

每个条目指向一个包含 `HOOK.md` 和 `handler.ts`（或 `index.ts`）的 Hook 目录。
Hook 包可以包含依赖项；它们将被安装在 `~/.openclaw/hooks/<id>` 下。

## Hook 结构

### HOOK.md 格式

`HOOK.md` 文件包含 YAML 前置元数据（Frontmatter）以及 Markdown 文档：

```markdown
---
name: my-hook
description: "关于此 Hook 功能的简短描述"
homepage: https://docs.clawd.bot/hooks#my-hook
metadata:
  { "openclaw": { "emoji": "🔗", "events": ["command:new"], "requires": { "bins": ["node"] } } }
---

# My Hook

详细文档写在这里...

## 功能

- 监听 `/new` 命令
- 执行某些操作
- 记录结果

## 要求

- 必须安装 Node.js

## 配置

无需配置。
```

### 元数据字段

`metadata.openclaw` 对象支持：

- **`emoji`**：CLI 显示的表情符号（例如 `"💾"`）
- **`events`**：要监听的事件数组（例如 `["command:new", "command:reset"]`）
- **`export`**：要使用的命名导出（默认为 `"default"`）
- **`homepage`**：文档 URL
- **`requires`**：可选要求
  - **`bins`**：PATH 环境变量中必需的二进制文件（例如 `["git", "node"]`）
  - **`anyBins`**：必须存在这其中的至少一个二进制文件
  - **`env`**：必需的环境变量
  - **`config`**：必需的配置路径（例如 `["workspace.dir"]`）
  - **`os`**：必需的操作系统平台（例如 `["darwin", "linux"]`）
- **`always`**：绕过资格检查（布尔值）
- **`install`**：安装方法（对于内置 Hooks：`[{"id":"bundled","kind":"bundled"}]`）

### 处理程序实现

`handler.ts` 文件导出一个 `HookHandler` 函数：

```typescript
import type { HookHandler } from "../../src/hooks/hooks.js";

const myHandler: HookHandler = async (event) => {
  // 仅在 'new' 命令时触发
  if (event.type !== "command" || event.action !== "new") {
    return;
  }

  console.log(`[my-hook] New command triggered`);
  console.log(`  Session: ${event.sessionKey}`);
  console.log(`  Timestamp: ${event.timestamp.toISOString()}`);

  // 在这里编写你的自定义逻辑

  // 可选：向用户发送消息
  event.messages.push("✨ My hook executed!");
};

export default myHandler;
```

#### 事件上下文

每个事件包括：

```typescript
{
  type: 'command' | 'session' | 'agent' | 'gateway',
  action: string,              // 例如 'new', 'reset', 'stop'
  sessionKey: string,          // 会话标识符
  timestamp: Date,             // 事件发生时间
  messages: string[],          // 推送消息到此处以发送给用户
  context: {
    type: 'command' | 'session' | 'agent' | 'gateway',
    scope: 'hook',
    payload: {
      sessionEntry?: SessionEntry,
      sessionId?: string,
      sessionFile?: string,
      commandSource?: string,    // 例如 'whatsapp', 'telegram'
      senderId?: string,
      workspaceDir?: string,
      bootstrapFiles?: WorkspaceBootstrapFile[],
      cfg?: ClawdbotConfig
    }
  }
}
```

## 事件类型

### 命令事件 (Command Events)

当发出 Agent 命令时触发：

- **`command`**：所有命令事件（通用监听器）
- **`command:new`**：当发出 `/new` 命令时
- **`command:reset`**：当发出 `/reset` 命令时
- **`command:stop`**：当发出 `/stop` 命令时

### Agent 事件 (Agent Events)

- **`agent:bootstrap`**：在注入工作区引导文件之前（Hooks 可以修改 `context.bootstrapFiles`）

### 网关事件 (Gateway Events)

当网关启动时触发：

- **`gateway:startup`**：在通道启动并且 Hooks 加载之后

### 工具结果 Hooks（插件 API）

这些 Hooks 不是事件流监听器；它们允许插件在 openclaw-cn 持久化工具结果之前同步调整结果。

- **`tool_result_persist`**：在工具结果写入会话记录之前对其进行转换。必须是同步的；返回更新后的工具结果负载，或返回 `undefined` 以保持原样。请参阅 [Agent 循环](/concepts/agent-loop)。

### 未来计划的事件

计划中的事件类型：

- **`session:start`**：当新会话开始时
- **`session:end`**：当会话结束时
- **`agent:error`**：当 Agent 遇到错误时
- **`message:sent`**：当消息发送时
- **`message:received`**：当收到消息时

## 创建自定义 Hooks

### 1. 选择位置

- **工作区 Hooks** (`<workspace>/hooks/`)：每个 Agent 独立，优先级最高
- **托管 Hooks** (`~/.openclaw/hooks/`)：跨工作区共享

### 2. 创建目录结构

```bash
mkdir -p ~/.openclaw/hooks/my-hook
cd ~/.openclaw/hooks/my-hook
```

### 3. 创建 HOOK.md

```markdown
---
name: my-hook
description: "做一些有用的事情"
metadata: { "openclaw": { "emoji": "🎯", "events": ["command:new"] } }
---

# My Custom Hook

当你发出 `/new` 时，此 Hook 会做一些有用的事情。
```

### 4. 创建 handler.ts

```typescript
import type { HookHandler } from "../../src/hooks/hooks.js";

const handler: HookHandler = async (event) => {
  if (event.type !== "command" || event.action !== "new") {
    return;
  }

  console.log("[my-hook] Running!");
  // 你的逻辑
};

export default handler;
```

### 5. 启用并测试

```bash
# 验证 Hook 是否被发现
openclaw-cn hooks list

# 启用它
openclaw-cn hooks enable my-hook

# 重启你的网关进程（macOS 上重启菜单栏应用，或者重启你的开发进程）

# 触发事件
# 通过你的消息通道发送 /new
```

## 配置

### 新配置格式（推荐）

```json
{
  "hooks": {
    "internal": {
      "enabled": true,
      "entries": {
        "session-memory": { "enabled": true },
        "command-logger": { "enabled": false }
      }
    }
  }
}
```

### 单个 Hook 配置

Hooks 可以有自定义配置：

```json
{
  "hooks": {
    "internal": {
      "enabled": true,
      "entries": {
        "my-hook": {
          "enabled": true,
          "env": {
            "MY_CUSTOM_VAR": "value"
          }
        }
      }
    }
  }
}
```

### 额外目录

从其他目录加载 Hooks：

```json
{
  "hooks": {
    "internal": {
      "enabled": true,
      "load": {
        "extraDirs": ["/path/to/more/hooks"]
      }
    }
  }
}
```

### 旧版配置格式（仍然支持）

旧的配置格式仍然有效，以保持向后兼容性：

```json
{
  "hooks": {
    "internal": {
      "enabled": true,
      "handlers": [
        {
          "event": "command:new",
          "module": "./hooks/handlers/my-handler.ts",
          "export": "default"
        }
      ]
    }
  }
}
```

**迁移**：对新 Hooks 使用基于发现的系统。旧版处理程序会在基于目录的 Hooks 之后加载。

## CLI 命令

### 列出 Hooks

```bash
# 列出所有 Hooks
openclaw-cn hooks list

# 仅显示符合条件的 Hooks
openclaw-cn hooks list --eligible

# 详细输出（显示缺失的要求）
openclaw-cn hooks list --verbose

# JSON 输出
openclaw-cn hooks list --json
```

### Hook 信息

```bash
# 显示关于某个 Hook 的详细信息
openclaw-cn hooks info session-memory

# JSON 输出
openclaw-cn hooks info session-memory --json
```

### 检查资格 (Check Eligibility)

```bash
# 显示资格摘要
openclaw-cn hooks check

# JSON 输出
openclaw-cn hooks check --json
```

### 启用/禁用

```bash
# 启用 Hook
openclaw-cn hooks enable session-memory

# 禁用 Hook
openclaw-cn hooks disable command-logger
```

## 内置 Hooks

### session-memory

当你发出 `/new` 时，将会话上下文保存到记忆中。

**事件**：`command:new`

**要求**：必须配置 `workspace.dir`

**输出**：`<workspace>/memory/YYYY-MM-DD-slug.md`（默认为 `~/clawd`）

**功能逻辑**：

1. 使用重置前的会话条目来定位正确的记录 (transcript)
2. 提取最后 15 行对话
3. 使用 LLM 生成描述性的文件名标识符 (slug)
4. 将会话元数据保存到带日期的记忆文件中

**输出示例**：

```markdown
# Session: 2026-01-16 14:30:00 UTC

- **Session Key**: agent:main:main
- **Session ID**: abc123def456
- **Source**: telegram
```

**文件名示例**：

- `2026-01-16-vendor-pitch.md`
- `2026-01-16-api-design.md`
- `2026-01-16-1430.md`（如果标识符生成失败，回退到时间戳）

**启用**：

```bash
openclaw-cn hooks enable session-memory
```

### command-logger

将所有命令事件记录到中心化的审计文件中。

**事件**：`command`

**要求**：无

**输出**：`~/.openclaw/logs/commands.log`

**功能逻辑**：

1. 捕获事件详情（命令动作、时间戳、会话 Key、发送者 ID、来源）
2. 以 JSONL 格式追加到日志文件
3. 在后台静默运行

**日志条目示例**：

```jsonl
{"timestamp":"2026-01-16T14:30:00.000Z","action":"new","sessionKey":"agent:main:main","senderId":"+1234567890","source":"telegram"}
{"timestamp":"2026-01-16T15:45:22.000Z","action":"stop","sessionKey":"agent:main:main","senderId":"user@example.com","source":"whatsapp"}
```

**查看日志**：

```bash
# 查看最近的命令
tail -n 20 ~/.openclaw/logs/commands.log

# 使用 jq 格式化打印
cat ~/.openclaw/logs/commands.log | jq .

# 按动作过滤
grep '"action":"new"' ~/.openclaw/logs/commands.log | jq .
```

**启用**：

```bash
openclaw-cn hooks enable command-logger
```

### soul-evil

在清理窗口期间或随机情况下，将注入的 `SOUL.md` 内容替换为 `SOUL_EVIL.md`。

**事件**：`agent:bootstrap`

**文档**：[SOUL Evil Hook](/hooks/soul-evil)

**输出**：不写入文件；替换仅发生在内存中。

**启用**：

```bash
openclaw-cn hooks enable soul-evil
```

**配置**：

```json
{
  "hooks": {
    "internal": {
      "enabled": true,
      "entries": {
        "soul-evil": {
          "enabled": true,
          "file": "SOUL_EVIL.md",
          "chance": 0.1,
          "purge": { "at": "21:00", "duration": "15m" }
        }
      }
    }
  }
}
```

### boot-md

当网关启动时（通道启动后）运行 `BOOT.md`。
必须启用内部 Hooks 才能运行此功能。

**事件**：`gateway:startup`

**要求**：必须配置 `workspace.dir`

**功能逻辑**：

1. 从你的工作区读取 `BOOT.md`
2. 通过 Agent 运行器 (runner) 执行指令
3. 通过消息工具发送任何请求的出站消息

**启用**：

```bash
openclaw-cn hooks enable boot-md
```

## 最佳实践

### 保持处理程序快速

Hooks 在命令处理期间运行。保持它们轻量：

```typescript
// ✓ 好 - 异步工作，立即返回
const handler: HookHandler = async (event) => {
  void processInBackground(event); // 触发即遗忘 (Fire and forget)
};

// ✗ 坏 - 阻塞命令处理
const handler: HookHandler = async (event) => {
  await slowDatabaseQuery(event);
  await evenSlowerAPICall(event);
};
```

### 优雅地处理错误

始终包裹有风险的操作：

```typescript
const handler: HookHandler = async (event) => {
  try {
    await riskyOperation(event);
  } catch (err) {
    console.error("[my-handler] Failed:", err instanceof Error ? err.message : String(err));
    // 不要抛出异常 - 让其他处理程序继续运行
  }
};
```

### 尽早过滤事件

如果事件不相关，尽早返回：

```typescript
const handler: HookHandler = async (event) => {
  // 只处理 'new' 命令
  if (event.type !== "command" || event.action !== "new") {
    return;
  }

  // 你的逻辑
};
```

### 使用具体的事件 Key

尽可能在元数据中指定确切的事件：

```yaml
metadata: { "openclaw": { "events": ["command:new"] } } # 具体
```

而不是：

```yaml
metadata: { "openclaw": { "events": ["command"] } } # 通用 - 开销更大
```

## 调试

### 启用 Hook 日志

网关在启动时会记录 Hook 的加载情况：

```
Registered hook: session-memory -> command:new
Registered hook: command-logger -> command
Registered hook: boot-md -> gateway:startup
```

### 检查发现 (Check Discovery)

列出所有已发现的 Hooks：

```bash
openclaw-cn hooks list --verbose
```

### 检查注册

在你的处理程序中，记录它何时被调用：

```typescript
const handler: HookHandler = async (event) => {
  console.log("[my-handler] Triggered:", event.type, event.action);
  // 你的逻辑
};
```

### 验证资格 (Verify Eligibility)

检查为什么一个 Hook 不符合条件：

```bash
openclaw-cn hooks info my-hook
```

在输出中查找缺失的要求。

## 测试

### 网关日志

监控网关日志以查看 Hook 执行情况：

```bash
# macOS
./scripts/clawlog.sh -f

# 其他平台
tail -f ~/.openclaw/gateway.log
```

### 直接测试 Hooks

隔离测试你的处理程序：

```typescript
import { test } from "vitest";
import { createHookEvent } from "./src/hooks/hooks.js";
import myHandler from "./hooks/my-hook/handler.js";

test("my handler works", async () => {
  const event = createHookEvent("command", "new", "test-session", {
    foo: "bar",
  });

  await myHandler(event);

  // 断言副作用
});
```

## 架构

### 核心组件

- **`src/hooks/types.ts`**：类型定义
- **`src/hooks/workspace.ts`**：目录扫描和加载
- **`src/hooks/frontmatter.ts`**：HOOK.md 元数据解析
- **`src/hooks/config.ts`**：资格检查
- **`src/hooks/hooks-status.ts`**：状态报告
- **`src/hooks/loader.ts`**：动态模块加载器
- **`src/cli/hooks-cli.ts`**：CLI 命令
- **`src/gateway/server-startup.ts`**：在网关启动时加载 Hooks
- **`src/auto-reply/reply/commands-core.ts`**：触发命令事件

### 发现流程 (Discovery Flow)

```
网关启动
    ↓
扫描目录 (工作区 → 托管 → 内置)
    ↓
解析 HOOK.md 文件
    ↓
检查资格 (二进制文件, 环境变量, 配置, 操作系统)
    ↓
从符合条件的 Hooks 加载处理程序
    ↓
为事件注册处理程序
```

### 事件流程 (Event Flow)

```
用户发送 /new
    ↓
命令验证
    ↓
创建 Hook 事件
    ↓
触发 Hook (所有已注册的处理程序)
    ↓
命令处理继续
    ↓
会话重置
```

## 故障排除

### Hook 未被发现

1. 检查目录结构：

   ```bash
   ls -la ~/.openclaw/hooks/my-hook/
   # 应该显示: HOOK.md, handler.ts
   ```

2. 验证 HOOK.md 格式：

   ```bash
   cat ~/.openclaw/hooks/my-hook/HOOK.md
   # 应该有包含 name 和 metadata 的 YAML 前置元数据
   ```

3. 列出所有发现的 Hooks：
   ```bash
   openclaw-cn hooks list
   ```

### Hook 不符合条件 (Not Eligible)

检查要求：

```bash
openclaw-cn hooks info my-hook
```

查找缺失项：

- 二进制文件（检查 PATH）
- 环境变量
- 配置值
- 操作系统兼容性

### Hook 未执行

1. 验证 Hook 是否启用：

   ```bash
   openclaw-cn hooks list
   # 应该在已启用的 Hooks 旁边显示 ✓
   ```

2. 重启你的网关进程，以便重新加载 Hooks。

3. 检查网关日志是否有错误：
   ```bash
   ./scripts/clawlog.sh | grep hook
   ```

### 处理程序错误

检查 TypeScript/导入 错误：

```bash
# 直接测试导入
node -e "import('./path/to/handler.ts').then(console.log)"
```

## 迁移指南

### 从旧版配置迁移到自动发现

**以前**：

```json
{
  "hooks": {
    "internal": {
      "enabled": true,
      "handlers": [
        {
          "event": "command:new",
          "module": "./hooks/handlers/my-handler.ts"
        }
      ]
    }
  }
}
```

**现在**：

1. 创建 Hook 目录：

   ```bash
   mkdir -p ~/.openclaw/hooks/my-hook
   mv ./hooks/handlers/my-handler.ts ~/.openclaw/hooks/my-hook/handler.ts
   ```

2. 创建 HOOK.md：

   ```markdown
   ---
   name: my-hook
   description: "My custom hook"
   metadata: { "openclaw": { "emoji": "🎯", "events": ["command:new"] } }
   ---

   # My Hook

   Does something useful.
   ```

3. 更新配置：

   ```json
   {
     "hooks": {
       "internal": {
         "enabled": true,
         "entries": {
           "my-hook": { "enabled": true }
         }
       }
     }
   }
   ```

4. 验证并重启你的网关进程：
   ```bash
   openclaw-cn hooks list
   # 应该显示： 🎯 my-hook ✓
   ```

**迁移的好处**：

- 自动发现
- CLI 管理
- 资格/适用性检查
- 更好的文档
- 一致的结构

## 另请参阅

- [CLI参考：hooks](/cli/hooks)
- [内置 Hooks README](https://github.com/clawdbot/clawdbot/tree/main/src/hooks/bundled)
- [Webhook Hooks](/automation/webhook)
- [配置](/gateway/configuration#hooks)
