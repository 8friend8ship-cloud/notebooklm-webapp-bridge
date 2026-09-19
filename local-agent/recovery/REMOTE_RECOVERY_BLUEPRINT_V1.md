# Remote Recovery Blueprint V1

P0 first-check template for RemoteDC/offline, PowerShell window storms, unexpected sleep, and automation-loop failures.

Node order:
N00 LOAD_LAST_GOOD -> N10 POWER_GUARD -> N20 TASK_TOPOLOGY -> N30 LOOP_SERIALIZATION -> N40 REMOTE_LOCAL_CHAIN -> N50 AUTH_GATE -> N60 REMOTE_MCP_X2 -> N70 DATA_PLANE_X2 -> N80 TASK_RESTORE -> N90 CONSISTENCY_RECEIPT.

Rules:
- Read latest state before changing anything.
- Resume from FIRST_UNFINISHED / first_failed_node.
- Do not repeat unchanged PASS nodes.
- No visible scheduled PowerShell.
- Prefer pythonw + CREATE_NO_WINDOW + per-task lock + global serialization.
- Preserve one RemoteDC producer chain.
- Live process/transport evidence outranks stale failure logs.
- Security/device approval is human-only and one-flow-only.
- Finish only after ping X2, harmless write/read X2, task readback, and all-store consistency receipt.
