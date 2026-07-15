# AI Thinking Mode

AI thinking mode controls the analysis level used before the Memory Book generates an answer. It only affects the thinking or reasoning parameters sent to the model and does not change local keyword search, record reading, search scope, or Markdown files.

## Available Levels

- **Off**: No additional thinking process is requested; answers can still be generated normally.
- **High**: Requests a higher level of thinking or reasoning processing.
- **Max**: Requests the highest level supported by the current protocol.

The thinking level may affect model processing time and token usage. Whether visible thinking content is ultimately returned depends on the provider protocol, model capabilities, and server response format.

## Protocol Mapping

The application translates the UI level based on the provider's request protocol and does not send the same level name to all services:

| Memory Book Level | Services Supporting Thinking | Services Supporting Reasoning |
| --- | --- | --- |
| Off | Thinking disabled | No reasoning level sent; uses standard answer parameters |
| High | `high` | `high` |
| Max | `max` | `xhigh` |

Here, `Max` is an application UI level and does not imply all providers use the same parameter name. Chat protocols use `max`, Responses protocols use `xhigh`.

## Unsupported or Failed Requests

If the provider does not support the selected thinking level, the model does not accept the corresponding parameter, or the parameter does not match the protocol, the current AI request returns an error. Existing search results, already-read local notes, and conversation history are unaffected.

Disabling thinking mode does not bypass provider authentication, missing models, network failures, or protocol errors; these issues still cause the current request to fail.
