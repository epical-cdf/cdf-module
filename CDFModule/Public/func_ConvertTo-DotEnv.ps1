Function ConvertTo-DotEnv {
    <#
        .SYNOPSIS
        Converts array or hashtable to .env file format.

        .DESCRIPTION
        Converts array or hashtable to .env file format. Arrays are tested for either a list of name-value pair arrays or array of name and value column.
        For 2x2 arrays it will be treated as name-value pairs. To be able to pipe

        .PARAMETER DotEnvSource
        The input object that holds the content to be converted to .env file format. It can be a Dictionary/Hashtable or Array.

        .INPUTS
        DotEnvSource can be piped into the command instead of passing it as an argument.

        .OUTPUTS
        None.

        .EXAMPLE
        ConvertTo-CdfDotEnv -DotEnvSource @{ Name1 = 'Value1', Name2 = 'Value2' }
        Name2=Value2
        Name1=Value1

        .EXAMPLE
        ,@( @('Name1', 'Value1'), @('Name2', 'Value2') ) | ConvertTo-CdfDotEnv
        # The arrat is treated as a 2x2 name-value pair array, mind the beginning comma to treat arrays as one parameter input
        Name2=Value2
        Name1=Value1

        .EXAMPLE
        ConvertTo-CdfDotEnv @( @('Name1', 'Name2', 'Name3', 'Name4'), @('Value1', 'Value2', 'Value3', 'Value4') )
        # This array is treated as separate name and value columnd arrays
        Name1=Value1
        Name2=Value2
        Name3=Value3
        Name4=Value4

        .EXAMPLE
        ConvertTo-CdfDotEnv @( @('Name1', 'Name2'), @('Value1', 'Value2') )
        # This array is treated as a 2x2 name-value pair array although that is likely not what was intended.
        Name1=Name2
        Value1=Value2

    #>

    Param(
        [Parameter(ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true, Mandatory = $true, Position = 0)]
        $DotEnvSource
    )

    begin {
    }
    process {
        $IsArrKV = $false
        $DotEnvString = [System.Text.StringBuilder]""
        if ('Object[]' -eq $DotEnvSource.GetType().Name -and $DotEnvSource.Length -gt 0) {
            # Determine type of array
            for ($i = 0; $i -lt $DotEnvSource.Count; $i++) {
                $IsArrKV = $true
                if ($DotEnvSource[$i].Length -ne 2) {
                    $IsArrKV = $false
                }
            }
            Write-Verbose "Is array is determined to be key-value-pairs: $($IsArrKV ? 'YES': 'NO')"
        }

        if ('Object[]' -eq $DotEnvSource.GetType().Name -and $IsArrKV) {
            for ($i = 0; $i -lt $DotEnvSource.Count; $i++) {
                $DotEnvString.Append($DotEnvSource[$i][0]).Append('=').AppendLine($DotEnvSource[$i][1]) | Out-Null
            }
        }
        elseif ('Object[]' -eq $DotEnvSource.GetType().Name -and -not($IsArrKV)) {
            for ($i = 0; $i -lt $DotEnvSource[0].Count; $i++) {
                $DotEnvString.Append($DotEnvSource[0][$i]).Append('=').AppendLine($DotEnvSource[1][$i]) | Out-Null
            }
        }
        elseif ($DotEnvSource.GetType().Name -match '.*Hashtable' -or $DotEnvSource.GetType().Name -match '.*Dictionary' ) {
            foreach ($key in $DotEnvSource.Keys) {
                $DotEnvString.Append($key) | Out-Null
                $DotEnvString.Append('=') | Out-Null
                $DotEnvString.AppendLine($DotEnvSource[$key]) | Out-Null
            }
        }
    }
    end {
        return $DotEnvString.ToString()
    }

}