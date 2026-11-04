# PowerShell twin of deny-destructive.sh, for Windows without Git Bash, where the
# .sh guard never runs and a hook that cannot run does not block.
#
# Same fixed deny line as its twin. Only "exit 0 + deny JSON" and "exit 2" block;
# any other exit lets the call through, so an internal failure exits 2.
$ErrorActionPreference = 'Stop'

try {
    [void][Console]::In.ReadToEnd()
    [Console]::Out.Write('{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Destructive tools are disabled in Quality Supervisor: skills never delete Qase data."}}')
    exit 0
}
catch {
    [Console]::Error.WriteLine("deny-destructive.ps1: internal error, blocking the call.")
    exit 2
}
