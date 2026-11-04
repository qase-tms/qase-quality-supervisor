# PowerShell twin of deny-destructive-api.sh, for Windows without Git Bash.
#
# Mirrors its twin: over-broad on purpose (ANY "method": "delete" in the payload
# denies), the same fixed deny line, and exit 2 on any internal failure, since
# every other non-zero exit lets the call through.
$ErrorActionPreference = 'Stop'

try {
    $raw = [Console]::In.ReadToEnd()

    if ($raw -imatch '"method"[^"]*"delete"') {
        [Console]::Out.Write('{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"DELETE through qase_api is disabled in Quality Supervisor: skills never delete Qase data."}}')
    }

    exit 0
}
catch {
    [Console]::Error.WriteLine("deny-destructive-api.ps1: internal error, blocking the call.")
    exit 2
}
