
function New-TraceParent {
    <#
    .SYNOPSIS
    Generates a new random traceparent identity according to W3C Trace Context  specification
  
    .DESCRIPTION
    Setup the configuration for a new application instance within a platform. Output files stored at SourceDir using template.
    
    .EXAMPLE
    New-CdfTraceParent
  
    .LINK
    https://w3c.github.io/trace-context/
    
    .LINK
    https://learn.microsoft.com/en-us/azure/azure-monitor/app/distributed-trace-data#correlation-headers-using-w3c-tracecontext
    

    #>

    [CmdletBinding()]
    Param()
    # see spec: https://www.w3.org/TR/trace-context
    # version-format   = trace-id "-" parent-id "-" trace-flags
    # trace-id         = 32HEXDIGLC  ; 16 bytes array identifier. All zeroes forbidden
    # parent-id        = 16HEXDIGLC  ; 8 bytes array identifier. All zeroes forbidden
    # trace-flags      = 2HEXDIGLC   ; 8 bit flags. Currently, only one bit is used. See below for detail

    $VERSION = "00" # fixed in spec at 00
    $TRACE_ID = (1..32 | % { '{0:x}' -f (Get-Random -Max 16) }) -join ''
    $PARENT_ID = (1..16 | % { '{0:x}' -f (Get-Random -Max 16) }) -join ''
    $TRACE_FLAG = "01"   # sampled
    $TRACE_PARENT = "$VERSION-$TRACE_ID-$PARENT_ID-$TRACE_FLAG"

    return $TRACE_PARENT
}