Function Format-ElapsedTime($ts) {
    $elapsedTime = ''

    if ( $ts.TotalMinutes -gt 0 ) {
        $elapsedTime = [string]::Format( "{0:0}.{1:00} min", $ts.TotalMinutes, $ts.Seconds );
    }
    else {
        $elapsedTime = [string]::Format( "{0:0}.{1:000} s", $ts.Seconds, $ts.Milliseconds);
    }

    if ($ts.Hours -eq 0 -and $ts.Minutes -eq 0 -and $ts.Seconds -eq 0) {
        $elapsedTime = [string]::Format("{0:0} ms", $ts.TotalMilliseconds);
    }

    return $elapsedTime
}