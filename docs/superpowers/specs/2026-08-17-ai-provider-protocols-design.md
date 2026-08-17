# StudyFlow 多协议 AI 服务适配设计

## 状态

设计已获用户确认，待文档审阅后进入实现计划。

## 背景与目标

StudyFlow 当前在客户端直接调用用户配置的 OpenAI Chat Completions 兼容接口。该方式已经可以连接许多中转服务和本地模型网关，但不能直接连接使用不同请求格式和认证方式的 Anthropic Messages API 与 OpenAI Responses API。

本次目标是在不改变现有默认行为的前提下，增加两种协议适配，并让普通对话、上下文压缩、AI 建议以及 StudyFlow Agent 工具调用都通过统一的内部接口工作。

## 范围

### 本次包含

- OpenAI Chat Completions 协议，保持现有行为并作为默认值。
- OpenAI Responses API。
- Anthropic Messages API。
- 设置页协议选择、说明文字和旧配置迁移。
- 三种协议的普通文本响应解析。
- 三种协议的工具定义、工具调用、工具结果回传和最多 4 轮工具循环。
- 401、403、429、5xx、超时、协议格式错误的统一用户提示。
- 单元测试、设置页测试、协议请求和工具循环测试。

### 本次不包含

- 流式输出和 SSE 增量渲染。
- 图片、音频、视频、文件输入。
- Embeddings、Rerank 或图像生成接口。
- OpenAI Responses 的内置 Web Search、Computer Use 等专属远程工具。
- Anthropic 的供应商专属扩展能力。
- 将 AI Key 上传到 StudyFlow 服务端；密钥继续只保存在设备安全存储中。

## 用户体验

在“设置 → AI”中增加“接口协议”选择：

1. OpenAI Chat Completions（默认）
2. OpenAI Responses
3. Anthropic Messages

Base URL 仍由用户填写，界面根据协议显示端点规则：

| 协议 | 用户填写的 Base URL 示例 | 客户端请求端点 |
|---|---|---|
| OpenAI Chat Completions | `https://provider.example/v1` | `.../chat/completions` |
| OpenAI Responses | `https://provider.example/v1` | `.../responses` |
| Anthropic Messages | `https://api.anthropic.com` 或服务商文档指定地址 | `.../v1/messages`；若 Base URL 已含 `/v1`，不得重复追加 |

协议变更后，用户点击“保存”即可生效；“测试连接”使用当前协议发送最小请求。API Key 继续使用密码学安全存储，设置页不回填或显示已保存密钥。连接失败时展示协议、HTTP 状态和服务商返回的安全摘要，但不展示 API Key、完整请求体或账户数据。

## 架构

### 统一内部接口

保留 `AiRepository` 对上层的接口。新增一个协议枚举和协议适配层，建议结构为：

- `AiProtocol`：持久化 `openaiChatCompletions`、`openaiResponses`、`anthropicMessages`。
- `AiSettings`：增加 `protocol`，没有历史值时默认 OpenAI Chat Completions。
- `AiProtocolAdapter`：负责端点、认证、请求编码、响应归一化和工具循环。
- `HttpAiRepository`：负责组装 StudyFlow 的业务消息和工具，将协议细节交给适配器。
- 统一内部结果：文本内容、工具调用、工具调用 ID、工具参数和错误类型。

适配器不得改变现有 `AiWorkspaceChangeDraft`、`AiToolTrace` 和本地确认流程。模型只生成变更草案，用户确认后才写入日程或任务。

### OpenAI Chat Completions

- 端点：`POST /chat/completions`。
- 认证：`Authorization: Bearer`，值来自设备安全存储中的 API Key。
- 请求：`model`、`messages`、`temperature`、必要时的 `tools` 与 `tool_choice`。
- 响应：读取 `choices[0].message.content` 和 `choices[0].message.tool_calls`。
- 工具结果：使用 `role: tool`、`tool_call_id` 和 JSON 字符串内容回传。

### OpenAI Responses

- 端点：`POST /responses`。
- 认证：`Authorization: Bearer`，值来自设备安全存储中的 API Key。
- 普通输入：将系统消息、历史消息和当前用户消息转换为 Responses 输入项。
- 工具定义：转换为 Responses function 工具结构，保持工具名、说明和 JSON Schema。
- 工具调用：解析 `function_call` 输出项中的调用 ID、名称和 JSON 参数。
- 工具结果：使用对应调用 ID 的 `function_call_output` 输入项回传。
- 文本响应：优先读取 `output_text`，必要时从 `output` 中的 message/content 文本块归一化。
- 兼容性：不假设 Responses 的 `output` 顺序，只处理已知的 message、function_call 和文本块类型。

### Anthropic Messages

- 端点：`POST /v1/messages`；Base URL 拼接逻辑避免重复 `/v1`。
- 认证：`x-api-key` 的值来自设备安全存储中的 API Key，并发送 `anthropic-version`；不发送 Bearer 认证作为唯一认证方式。
- 请求：`model`、顶层 `system`、`messages`、必需的 `max_tokens`，必要时的 `tools` 与 `tool_choice`。
- 历史消息：将系统消息提取到顶层；用户和助手消息保留为 Messages 角色。
- 工具定义：转换为 `name`、`description`、`input_schema`。
- 工具调用：解析助手消息 content blocks 中的 `tool_use`。
- 工具结果：追加用户消息，content 中包含对应的 `tool_result`，随后继续请求。
- 文本响应：拼接所有文本 content blocks；空文本响应视为协议错误。

## Agent 工具策略

三种协议对外暴露相同的 StudyFlow 工具：

- `get_current_time`
- `get_schedule_blocks`
- `get_medication_plans`
- `get_schedule_feedback`
- `propose_workspace_changes`

工具调用流程：

1. 根据用户消息和当前业务数据构造统一内部消息。
2. 发送带工具定义的协议请求。
3. 若模型返回文本，直接归一化为 `AiCoachReply`。
4. 若模型返回工具调用，校验工具名和 JSON 参数。
5. 在客户端执行只读查询或生成待确认草案。
6. 记录脱敏后的 `AiToolTrace`。
7. 将工具结果按当前协议格式回传，继续请求最终文本。
8. 最多处理 4 轮工具调用；超限时返回可读错误，不应用任何变更。

如果服务商不支持工具调用：

- 普通对话和不依赖工具的 AI 建议仍可工作。
- 需要实时日程、服药计划或修改草案时，显示“当前模型不支持 Agent 工具”，不能伪造查询结果或直接修改数据。

## 配置迁移

在安全存储中增加协议键，例如 `studyflow.ai.protocol.v1`。读取旧配置时：

- 缺少协议键：使用 `openaiChatCompletions`。
- 协议值未知：回退到默认协议并提示用户重新选择。
- Base URL、模型、Key、启用状态保持原值。

服务端不增加 AI 环境变量、数据库字段或 AI 路由。

## 错误处理

统一把错误分为：

- 认证失败：401、403。
- 限流或配额：429。
- 服务商不可用：500、502、503、504。
- 网络错误：DNS、连接重置、TLS、超时。
- 协议错误：缺少必需字段、响应结构不符合所选协议。
- 能力错误：模型不支持工具调用或服务商拒绝工具格式。

错误消息应包含当前协议和 HTTP 状态，若服务商返回 JSON，只提取安全的 `code`、`type` 或 `message` 摘要。不得把认证头、原始 API Key、完整响应或工具参数中的账户数据写入日志或聊天气泡。

## 测试计划

### 单元测试

- 三种协议的 Base URL 端点拼接。
- OpenAI Bearer、Anthropic `x-api-key` 和版本头。
- 三种协议的普通文本响应解析。
- 三种协议的工具定义编码。
- 三种协议的工具调用解析和工具结果回传。
- 多轮工具调用与 4 轮上限。
- 不支持工具时的可读错误。
- 503 响应的错误摘要和密钥脱敏。
- 历史 AI 设置缺少协议键时默认兼容。

### 客户端验证

- AI 设置页可以选择并保存三种协议。
- 旧配置升级后仍能正常测试连接。
- 日程、任务、服药查询和变更草案在三种协议下维持现有确认流程。
- API Key 保存后不回显。
- 全量 Flutter 测试、静态分析通过。

## 验收标准

1. 现有 OpenAI Chat Completions 配置无需修改即可继续工作。
2. 使用 OpenAI Responses API 的兼容服务可以完成普通对话和工具调用。
3. 使用 Anthropic Messages API 的服务可以完成普通对话和工具调用。
4. 三种协议均不会绕过用户确认而修改任务或日程。
5. 协议错误、服务商 503 和模型能力不足能够被用户区分。
6. API Key 不进入服务端、日志、Git 或聊天消息。
7. 不支持流式、多模态和供应商专属能力的限制在设置页或文档中明确说明。
