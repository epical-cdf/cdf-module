Function Enable-Prompt {
  Set-Content function:\prompt $Global:CdfPrompt
  $Global:CdfPromptEnabled = $true
}