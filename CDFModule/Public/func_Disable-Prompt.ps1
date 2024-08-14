Function Disable-Prompt {
  Set-Content function:\prompt $Global:CdfPromptBackup
  $Global:CdfPromptEnabled = $false
}
