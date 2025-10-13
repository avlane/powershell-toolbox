# Troubleshooting

This page lists the places where the module is most likely to go wrong.

## Remote computers

Most commands that take `-ComputerName` use CIM over WinRM (WSMan), or
`Invoke-Command`.

- **"WinRM cannot process the request"**: check from the machine you run on with
  `Test-WSMan -ComputerName SERVER`. On the target, `Enable-PSRemoting -Force` (or
  the group policy that does it) is needed, and TCP 5985/5986 must be reachable.
- **Access denied**: the account you run as must be an administrator on the target
  for CIM queries of Win32 classes and for the certificate store. Run PowerShell
  as that account; the commands do not take a credential for CIM.
- **A server that only allows DCOM**: the commands do not fall back to DCOM. Create a
  `New-CimSession -SessionOption (New-CimSessionOption -Protocol Dcom)` yourself and
  use `Get-CimInstance -CimSession` directly, or use `Get-PtScheduledTaskReport
  -CimSession`, which takes sessions.
- **Second hop**: running these commands inside a remote session and reaching a third
  machine needs delegation (CredSSP or Kerberos constrained delegation).

## SQL Server

- **"A connection was successfully established with the server, but then an error
  occurred during the login process" / certificate chain not trusted**: recent
  SqlServer module versions encrypt by default. Fix the certificate, or pass
  `-TrustServerCertificate` to `Invoke-PtSqlQuery` on a network you trust.
- **"This version of Invoke-Sqlcmd has no -TrustServerCertificate parameter"**:
  `Update-Module SqlServer`. Old versions (before 22.x) have no such parameter and no
  encryption by default.
- **Invoke-Sqlcmd not found**: `Install-Module SqlServer`. The older SQLPS module
  also provides it but is not supported here.
- **Empty results for a query that works in SSMS**: `Invoke-Sqlcmd` returns nothing
  for statements that return no rows, and only the first result set of a batch.
- **Numbers that look wrong in `Get-PtBackupStatus`**: ages are measured against the
  server's clock (`GETDATE()`), not yours.

## Jira Cloud

- **401 Unauthorized**: the user name is the account's e-mail address and the password
  is an API token, not the account password. Tokens are created at
  <https://id.atlassian.com/manage-profile/security/api-tokens>.
- **403 / "CAPTCHA_CHALLENGE"**: too many failed logins; sign in to the site in a
  browser once.
- **429**: the commands retry after `Retry-After`. Persistent 429s mean the script is
  too chatty; use `-MaxTotalDelaySeconds` to fail instead of waiting.
- **Search returns an error about an unbounded query**: the enhanced search endpoint
  rejects queries without any restriction (add a `project =` or a date range).
- **Assignee not found**: Jira Cloud uses account ids; look them up with
  `Find-PtJiraUser`.
- **Description or comment looks like JSON**: v3 of the API returns Atlassian
  Document Format; `Get-PtJiraIssue` converts it to text, the raw cmdlets do not.

## Secrets

- **SecretStore asks for a password each time**: configure it once with
  `Set-SecretStoreConfiguration` (choose `-Authentication Password` and a timeout, or
  `-Authentication None` on a machine you trust). `Initialize-PtVault` does not do this
  for you on purpose.
- **`Get-PtSecret` fails in a scheduled task**: SecretStore vaults belong to a user
  profile; the task must run as the user who created the secret.

## Tests

- **Mocks have no effect in parallel code**: `ForEach-Object -Parallel` runs in other
  runspaces. The tests pass `-ThrottleLimit 1` for that reason.
- **"Could not find Command Get-AzVM" (or similar) when mocking**: the real module is not
  installed; the tests define stand-in functions first. If you add a test for a command
  from another module, do the same.
- **Tests for the scheduled task commands are skipped**: they only run on Windows.
