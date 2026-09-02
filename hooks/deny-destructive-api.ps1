# PowerShell twin of deny-destructive-api.sh, for Windows without Git Bash.
#
# Mirrors its twin's two deliberate choices:
#  1. Fail-closed — any internal failure exits 2 rather than letting a DELETE
#     through. Only "exit 0 + deny JSON" and "exit 2" block; every other
#     non-zero exit is non-blocking and the call proceeds.
#  2. Detection is deliberately over-broad — ANY "method": "delete" anywhere in
#     the payload denies, rather than resolving tool_input.method precisely. A
#     decoy or nested method field can only cause an unnecessary denial, never
#     an unnoticed deletion.
$ErrorActionPreference = 'Stop'

try {
    $raw = [Console]::In.ReadToEnd()

    if ($raw -imatch '"method"\s*:\s*"delete"') {
        $reason = 'DELETE via the qase_api escape hatch is disabled in Quality Supervisor - skills never delete Qase data, including through the raw API passthrough.'
        $out = @{
            hookSpecificOutput = @{
                hookEventName            = 'PreToolUse'
                permissionDecision       = 'deny'
                permissionDecisionReason = $reason
            }
        } | ConvertTo-Json -Depth 5 -Compress
        [Console]::Out.Write($out)
    }

    # Anything else: no output, normal permission flow continues.
    exit 0
}
catch {
    [Console]::Error.WriteLine("deny-destructive-api.ps1: unexpected internal error - blocking call as a precaution.")
    exit 2
}
