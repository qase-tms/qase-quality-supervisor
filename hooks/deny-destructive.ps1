# PowerShell twin of deny-destructive.sh, for Windows without Git Bash, where the
# .sh guard is never executed and a hook that cannot run does not block.
#
# FAIL-CLOSED, exactly like its twin: any internal failure exits 2 rather than
# letting the call through. Per the PreToolUse contract only "exit 0 + deny JSON"
# and "exit 2" block; every other non-zero exit lets the tool proceed.
$ErrorActionPreference = 'Stop'

try {
    $raw = [Console]::In.ReadToEnd()
    $toolName = 'an unknown tool'
    if ($raw -match '"tool_name"\s*:\s*"([^"]*)"') { $toolName = $Matches[1] }

    $reason = "This plugin never deletes data in Qase. Blocked $toolName."
    $out = @{
        hookSpecificOutput = @{
            hookEventName            = 'PreToolUse'
            permissionDecision       = 'deny'
            permissionDecisionReason = $reason
        }
    } | ConvertTo-Json -Depth 5 -Compress

    [Console]::Out.Write($out)
    exit 0
}
catch {
    [Console]::Error.WriteLine("deny-destructive.ps1: internal error - blocking call as a precaution.")
    exit 2
}
