# Measurement reference

[English](metrics.md) · [简体中文](metrics.zh-CN.md) · [README](../README.md)

## Text-output average

The displayed speed comes from `PerformanceHistory.view(...).bodyAverage`. The menu and the panel round the same value to the nearest integer.

1. Group records by conversation, model, and reasoning effort.
2. Read official per-request output and reasoning counts from `token_usage_record`.
3. Reject requests containing generated `function_call` or `custom_tool_call` items. Subtracting reasoning alone would leave tool-argument tokens in the numerator.
4. Require complete, valid timing for the expected generation items. Missing or inconsistent records are not substituted with the subscription time.
5. Merge overlapping `AgentMessage` intervals within the request. Reasoning and tool-execution intervals are not part of this denominator.
6. Take the latest five eligible requests. Divide their combined text tokens (`output − reasoning`) by their combined text-interval seconds.

Example: two eligible requests report 200 text tokens over 4 seconds and 600 over 20 seconds. The combined rate is `800 / 24 ≈ 33 tok/s`, not the arithmetic mean of `50` and `30`.

These intervals describe client-visible message lifecycles. They do not isolate network delay or establish a server-side first-to-last-token decoding interval. Missing/filtered requests also introduce sample selection bias. Compare recent text delivery cautiously, not total model capability.

Stored samples survive idle periods, app restarts, and tool execution. The label shows the number actually available and the completion time of the newest sample. A model or effort change selects a different sample group. Older samples for that group may be reused; there is no time-based expiry.

## Turn timing

A **request** is a model response. A **turn** is the work associated with a user turn, which may include many model requests and tool calls.

- Running elapsed time uses the available turn start.
- Completed elapsed time uses official `task_complete.duration_ms / 1000`.
- Completed first-token latency uses official `time_to_first_token_ms / 1000`. It is neither a reasoning duration nor average request latency.
- Final-answer output is included in completed turn duration. A Codex UI label that stops before final-answer output can be smaller; the two labels need not share an endpoint.
- The UI shows one decimal place below a minute and truncates to whole minutes/seconds above a minute.
- Tool cumulative duration adds recorded tool item durations. Overlap and nesting mean it cannot safely be subtracted from turn duration to derive thinking time.

## Official usage

For a turn, complete `turn_token_usage` values replace previous values rather than being added repeatedly. Request IDs are deduplicated. Conversation totals prefer `thread_token_usage` over older `token_count` summaries.

Cached input is already part of input. Reasoning is already part of output. Neither is added a second time. Cache hit is computed within the same turn, displayed as a percentage rounded to two decimal places, and omitted when input is zero or unavailable. Context occupancy uses the latest request total and reported context window, not accumulated conversation usage.

## Unknown and disconnected data

Unavailable metrics are omitted or explained as pending; unknown values are not fabricated as zero. Recorded zero-duration tool items can still produce `0.0s` after rounding. While historical logs load, recovered samples may remain visible. On reconnection, snapshots and replayed text restore state without creating a burst of new live tokens.

The tokenizer-based three-second visible-text counter remains an internal diagnostic. It is not the persistent average shown in the menu bar. There is no reliable reasoning-speed or combined reasoning/output-speed metric in the current UI.
