#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

# Pester 5 tests for the Jira helpers. Nothing talks to Atlassian: the layer below
# (Invoke-PtRestRetry, or Invoke-PtJiraRequest) is mocked in every test.

BeforeAll {
    $manifest = Join-Path (Join-Path (Split-Path -Parent $PSScriptRoot) 'PowerShellToolbox') 'PowerShellToolbox.psd1'
    Import-Module $manifest -Force
}

Describe 'Connect-PtJira' {
    BeforeEach {
        InModuleScope PowerShellToolbox { $script:PtJira = $null }
        Mock Invoke-PtRestRetry -ModuleName PowerShellToolbox { }
    }

    It 'builds a basic authentication header from the e-mail address and token' {
        $secure = ConvertTo-SecureString 's3cr3t' -AsPlainText -Force
        $credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList 'avery@example.com', $secure
        Connect-PtJira -BaseUri 'https://example.atlassian.net/' -Credential $credential -SkipValidation | Out-Null

        Invoke-PtJiraRequest -Path '/rest/api/3/myself' | Out-Null
        Should -Invoke Invoke-PtRestRetry -ModuleName PowerShellToolbox -Times 1 -Exactly -ParameterFilter {
            $Uri -eq 'https://example.atlassian.net/rest/api/3/myself' -and $Headers.Authorization -eq 'Basic YXZlcnlAZXhhbXBsZS5jb206czNjcjN0'
        }
    }

    It 'does not return the token' {
        $secure = ConvertTo-SecureString 's3cr3t' -AsPlainText -Force
        $credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList 'avery@example.com', $secure
        $connection = Connect-PtJira -BaseUri 'https://example.atlassian.net' -Credential $credential -SkipValidation
        ($connection | Out-String) | Should -Not -Match 's3cr3t'
        $connection.Email | Should -Be 'avery@example.com'
    }

    It 'reads the environment with -FromEnvironment' {
        $oldEmail = $env:JIRA_EMAIL
        $oldToken = $env:JIRA_API_TOKEN
        try {
            $env:JIRA_EMAIL = 'avery@example.com'
            $env:JIRA_API_TOKEN = 's3cr3t'
            Connect-PtJira -BaseUri 'https://example.atlassian.net' -FromEnvironment -SkipValidation | Out-Null
            Invoke-PtJiraRequest -Path '/x' | Out-Null
            Should -Invoke Invoke-PtRestRetry -ModuleName PowerShellToolbox -Times 1 -Exactly -ParameterFilter { $Headers.Authorization -eq 'Basic YXZlcnlAZXhhbXBsZS5jb206czNjcjN0' }

            $env:JIRA_API_TOKEN = ''
            { Connect-PtJira -BaseUri 'https://example.atlassian.net' -FromEnvironment -SkipValidation } | Should -Throw '*JIRA_EMAIL and JIRA_API_TOKEN*'
        }
        finally {
            $env:JIRA_EMAIL = $oldEmail
            $env:JIRA_API_TOKEN = $oldToken
        }
    }

    It 'only accepts Jira Cloud addresses' {
        $secure = ConvertTo-SecureString 'x' -AsPlainText -Force
        $credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList 'a@example.com', $secure
        { Connect-PtJira -BaseUri 'https://jira.internal.example.com' -Credential $credential -SkipValidation } | Should -Throw
        { Connect-PtJira -BaseUri 'http://example.atlassian.net' -Credential $credential -SkipValidation } | Should -Throw
    }

    It 'forgets the connection when the check fails' {
        Mock Invoke-PtRestRetry -ModuleName PowerShellToolbox { throw '401 Unauthorized' }
        $secure = ConvertTo-SecureString 'wrong' -AsPlainText -Force
        $credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList 'avery@example.com', $secure
        { Connect-PtJira -BaseUri 'https://example.atlassian.net' -Credential $credential } | Should -Throw '*Could not sign in*'
        { Invoke-PtJiraRequest -Path '/rest/api/3/myself' } | Should -Throw '*Not connected*'
    }
}

Describe 'Invoke-PtJiraRequest' {
    BeforeEach {
        Mock Invoke-PtRestRetry -ModuleName PowerShellToolbox { }
        $secure = ConvertTo-SecureString 'x' -AsPlainText -Force
        $credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList 'a@example.com', $secure
        Connect-PtJira -BaseUri 'https://example.atlassian.net' -Credential $credential -SkipValidation | Out-Null
    }

    It 'sorts and URL-encodes the query string' {
        Invoke-PtJiraRequest -Path '/rest/api/3/search' -Query @{ maxResults = 50; jql = 'project = OPS' } | Out-Null
        Should -Invoke Invoke-PtRestRetry -ModuleName PowerShellToolbox -Times 1 -Exactly -ParameterFilter {
            $Uri -eq 'https://example.atlassian.net/rest/api/3/search?jql=project%20%3D%20OPS&maxResults=50'
        }
    }

    It 'adds extra headers to the authentication headers' {
        Invoke-PtJiraRequest -Path '/rest/api/3/issue/OPS-1/attachments' -Method Post -Form @{ file = 'x' } -Headers @{ 'X-Atlassian-Token' = 'no-check' } | Out-Null
        Should -Invoke Invoke-PtRestRetry -ModuleName PowerShellToolbox -Times 1 -Exactly -ParameterFilter {
            $Headers['X-Atlassian-Token'] -eq 'no-check' -and $Headers.ContainsKey('Authorization') -and $Form.file -eq 'x'
        }
    }

    It 'leaves the stored headers alone when it adds some' {
        Invoke-PtJiraRequest -Path '/x' -Headers @{ 'X-Extra' = '1' } | Out-Null
        Invoke-PtJiraRequest -Path '/x' | Out-Null
        Should -Invoke Invoke-PtRestRetry -ModuleName PowerShellToolbox -Times 1 -Exactly -ParameterFilter { -not $Headers.ContainsKey('X-Extra') }
    }

    It 'passes the method and body on' {
        Invoke-PtJiraRequest -Path '/rest/api/3/issue/OPS-1/comment' -Method Post -Body @{ a = 1 } | Out-Null
        Should -Invoke Invoke-PtRestRetry -ModuleName PowerShellToolbox -Times 1 -Exactly -ParameterFilter { $Method -eq 'Post' -and $Body.a -eq 1 }
    }
}

Describe 'Search-PtJiraIssue' {
    BeforeAll {
        function New-FakeIssue($key) {
            @{ key = $key; fields = @{
                summary = "Summary of $key"; issuetype = @{ name = 'Task' }
                status = @{ name = 'In Progress'; statusCategory = @{ name = 'In Progress' } }
                priority = @{ name = 'High' }
                assignee = @{ displayName = 'Sam Example'; accountId = '5b10a2844c20165700ede21g' }
                reporter = @{ displayName = 'Avery Lane' }
                created = '2020-08-30T10:11:12.345+0000'; updated = '2020-09-01T08:00:00.000+0200' } }
        }
        $global:PtTestIssues = @{ OPS1 = (New-FakeIssue 'OPS-1'); OPS2 = (New-FakeIssue 'OPS-2'); OPS3 = (New-FakeIssue 'OPS-3') }

        Mock Invoke-PtJiraRequest -ModuleName PowerShellToolbox -ParameterFilter { $Query.startAt -eq 0 } {
            [pscustomobject]@{ total = 3; issues = @($global:PtTestIssues.OPS1, $global:PtTestIssues.OPS2) }
        }
        Mock Invoke-PtJiraRequest -ModuleName PowerShellToolbox -ParameterFilter { $Query.startAt -eq 2 } {
            [pscustomobject]@{ total = 3; issues = @($global:PtTestIssues.OPS3) }
        }
        InModuleScope PowerShellToolbox { $script:PtJira = @{ BaseUri = 'https://example.atlassian.net'; Headers = @{} } }
    }

    AfterAll {
        Remove-Variable -Name PtTestIssues -Scope Global -ErrorAction SilentlyContinue
    }

    It 'reads every page' {
        $issues = @(Search-PtJiraIssue 'project = OPS' -PageSize 2)
        $issues.Key -join ',' | Should -Be 'OPS-1,OPS-2,OPS-3'
        Should -Invoke Invoke-PtJiraRequest -ModuleName PowerShellToolbox -Times 2 -Exactly
    }

    It 'flattens the issues' {
        $issue = Search-PtJiraIssue 'project = OPS' -PageSize 2 | Select-Object -First 1
        $issue.Summary | Should -Be 'Summary of OPS-1'
        $issue.Status | Should -Be 'In Progress'
        $issue.Assignee | Should -Be 'Sam Example'
        $issue.AssigneeAccountId | Should -Be '5b10a2844c20165700ede21g'
        $issue.Url | Should -Be 'https://example.atlassian.net/browse/OPS-1'
        $issue.Created.UtcDateTime | Should -Be ([datetime]::SpecifyKind([datetime]'2020-08-30 10:11:12.345', 'Utc'))
        $issue.Updated.UtcDateTime.Hour | Should -Be 6
    }

    It 'stops at -First' {
        @(Search-PtJiraIssue 'project = OPS' -PageSize 2 -First 1).Count | Should -Be 1
    }

    It 'returns the API objects with -Raw' {
        (Search-PtJiraIssue 'project = OPS' -PageSize 2 -Raw | Select-Object -First 1).key | Should -Be 'OPS-1'
    }
}

Describe 'Atlassian Document Format helpers' {
    It 'wraps each non-empty line in a paragraph' {
        $doc = InModuleScope PowerShellToolbox { ConvertTo-PtAdf -Text "first line`r`n`r`nsecond line" }
        $doc.type | Should -Be 'doc'
        $doc.version | Should -Be 1
        $doc.content.Count | Should -Be 2
        $doc.content[1].content[0].text | Should -Be 'second line'
    }

    It 'still produces a valid document for empty text' {
        $doc = InModuleScope PowerShellToolbox { ConvertTo-PtAdf -Text '' }
        $doc.content.Count | Should -Be 1
        $doc.content[0].type | Should -Be 'paragraph'
    }

    It 'extracts plain text from a document' {
        $text = InModuleScope PowerShellToolbox {
            $doc = [pscustomobject]@{ type = 'doc'; content = @(
                [pscustomobject]@{ type = 'paragraph'; content = @(
                    [pscustomobject]@{ type = 'text'; text = 'Hello ' },
                    [pscustomobject]@{ type = 'mention'; attrs = [pscustomobject]@{ text = '@Sam' } }
                ) },
                [pscustomobject]@{ type = 'paragraph'; content = @([pscustomobject]@{ type = 'text'; text = 'second' }) }
            ) }
            ConvertFrom-PtAdf -Node $doc
        }
        $text | Should -Be "Hello @Sam`nsecond`n"
    }

    It 'passes plain strings and nulls through' {
        InModuleScope PowerShellToolbox { ConvertFrom-PtAdf -Node 'plain' } | Should -Be 'plain'
        InModuleScope PowerShellToolbox { ConvertFrom-PtAdf -Node $null } | Should -Be ''
    }
}

Describe 'Add-PtJiraComment' {
    BeforeEach {
        Mock Invoke-PtJiraRequest -ModuleName PowerShellToolbox { [pscustomobject]@{ id = '10001'; created = '2020-09-20T11:00:00.000+0000' } }
    }

    It 'posts the text as an ADF document' {
        $result = Add-PtJiraComment -Key OPS-1 -Body 'hello'
        $result.CommentId | Should -Be '10001'
        Should -Invoke Invoke-PtJiraRequest -ModuleName PowerShellToolbox -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'Post' -and $Path -eq '/rest/api/3/issue/OPS-1/comment' -and $Body.body.content[0].content[0].text -eq 'hello'
        }
    }

    It 'does nothing with -WhatIf' {
        Add-PtJiraComment -Key OPS-1 -Body 'hello' -WhatIf | Out-Null
        Should -Invoke Invoke-PtJiraRequest -ModuleName PowerShellToolbox -Times 0 -Exactly
    }

    It 'rejects a malformed key' {
        { Add-PtJiraComment -Key 'not a key' -Body 'x' } | Should -Throw
    }
}

Describe 'Invoke-PtJiraTransition' {
    BeforeEach {
        Mock Get-PtJiraTransition -ModuleName PowerShellToolbox {
            @(
                [pscustomobject]@{ Key = 'OPS-1'; Id = '21'; Name = 'In Progress'; ToStatus = 'In Progress' },
                [pscustomobject]@{ Key = 'OPS-1'; Id = '31'; Name = 'Done'; ToStatus = 'Done' }
            )
        }
        Mock Invoke-PtJiraRequest -ModuleName PowerShellToolbox { }
    }

    It 'finds the transition by name, ignoring case' {
        $result = Invoke-PtJiraTransition -Key OPS-1 -Transition 'done'
        $result.ToStatus | Should -Be 'Done'
        Should -Invoke Invoke-PtJiraRequest -ModuleName PowerShellToolbox -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'Post' -and $Body.transition.id -eq '31' -and -not $Body.ContainsKey('update')
        }
    }

    It 'finds the transition by id and can add a comment' {
        Invoke-PtJiraTransition -Key OPS-1 -Transition '21' -Comment 'started' | Out-Null
        Should -Invoke Invoke-PtJiraRequest -ModuleName PowerShellToolbox -Times 1 -Exactly -ParameterFilter {
            $Body.transition.id -eq '21' -and $Body.update.comment[0].add.body.content[0].content[0].text -eq 'started'
        }
    }

    It 'lists the available transitions when there is no match' {
        { Invoke-PtJiraTransition -Key OPS-1 -Transition 'Reopen' } | Should -Throw "*Available now: In Progress (21), Done (31)*"
        Should -Invoke Invoke-PtJiraRequest -ModuleName PowerShellToolbox -Times 0 -Exactly
    }

    It 'does nothing with -WhatIf' {
        Invoke-PtJiraTransition -Key OPS-1 -Transition 'Done' -WhatIf | Out-Null
        Should -Invoke Invoke-PtJiraRequest -ModuleName PowerShellToolbox -Times 0 -Exactly
    }
}

Describe 'Find-PtJiraUser' {
    BeforeAll {
        Mock Invoke-PtJiraRequest -ModuleName PowerShellToolbox {
            @(
                [pscustomobject]@{ accountId = '5b10a2844c20165700ede21g'; displayName = 'Sam Example'; emailAddress = 'sam.example@example.com'; active = $true; accountType = 'atlassian' },
                [pscustomobject]@{ accountId = '5b10ac8d82e05b22cc7d4ef5'; displayName = 'Sam Examplewood'; emailAddress = $null; active = $true; accountType = 'atlassian' },
                [pscustomobject]@{ accountId = '557058:f58131cb-b67d-39f1-a8de-2fbd02a1b77f'; displayName = 'Old Sam'; emailAddress = $null; active = $false; accountType = 'atlassian' },
                [pscustomobject]@{ accountId = '5d1234567890ab0abcd12345'; displayName = 'Sam Bot'; emailAddress = $null; active = $true; accountType = 'app' }
            )
        }
    }

    It 'returns active people with their account ids' {
        $users = @(Find-PtJiraUser -Query 'sam')
        $users.DisplayName -join ',' | Should -Be 'Sam Example,Sam Examplewood'
        $users[0].AccountId | Should -Be '5b10a2844c20165700ede21g'
    }

    It 'includes inactive accounts and apps on request' {
        @(Find-PtJiraUser -Query 'sam' -IncludeInactive).Count | Should -Be 4
    }

    It 'keeps only exact matches with -Exact' {
        $users = @(Find-PtJiraUser -Query 'sam.example@example.com' -Exact)
        $users.Count | Should -Be 1
        $users[0].DisplayName | Should -Be 'Sam Example'
    }

    It 'passes the query and the limit on' {
        Find-PtJiraUser -Query 'sam' -First 5 | Out-Null
        Should -Invoke Invoke-PtJiraRequest -ModuleName PowerShellToolbox -ParameterFilter {
            $Path -eq '/rest/api/3/user/search' -and $Query.query -eq 'sam' -and $Query.maxResults -eq 5
        }
    }
}

Describe 'New-PtJiraIssue' {
    BeforeEach {
        Mock Invoke-PtJiraRequest -ModuleName PowerShellToolbox { [pscustomobject]@{ id = '10042'; key = 'OPS-42'; self = 'https://example.atlassian.net/rest/api/3/issue/10042' } }
        InModuleScope PowerShellToolbox { $script:PtJira = @{ BaseUri = 'https://example.atlassian.net'; Headers = @{} } }
    }

    It 'creates the issue and returns its key and address' {
        $issue = New-PtJiraIssue -ProjectKey OPS -Summary 'Disk F: is full' -Confirm:$false
        $issue.Key | Should -Be 'OPS-42'
        $issue.Url | Should -Be 'https://example.atlassian.net/browse/OPS-42'
    }

    It 'sends the fields the API expects' {
        New-PtJiraIssue -ProjectKey OPS -Summary 'Disk F: is full' -Description 'line one' -AssigneeAccountId 'abc123' -Label disk, sql -Priority High -ParentKey OPS-1 -Confirm:$false | Out-Null
        Should -Invoke Invoke-PtJiraRequest -ModuleName PowerShellToolbox -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'Post' -and $Path -eq '/rest/api/3/issue' -and
            $Body.fields.project.key -eq 'OPS' -and $Body.fields.summary -eq 'Disk F: is full' -and
            $Body.fields.issuetype.name -eq 'Task' -and $Body.fields.assignee.accountId -eq 'abc123' -and
            ($Body.fields.labels -join ',') -eq 'disk,sql' -and $Body.fields.priority.name -eq 'High' -and
            $Body.fields.parent.key -eq 'OPS-1' -and $Body.fields.description.type -eq 'doc'
        }
    }

    It 'leaves out the fields that were not given' {
        New-PtJiraIssue -ProjectKey OPS -Summary 'Minimal' -Confirm:$false | Out-Null
        Should -Invoke Invoke-PtJiraRequest -ModuleName PowerShellToolbox -Times 1 -Exactly -ParameterFilter {
            -not $Body.fields.Contains('assignee') -and -not $Body.fields.Contains('labels') -and -not $Body.fields.Contains('description')
        }
    }

    It 'does nothing with -WhatIf' {
        New-PtJiraIssue -ProjectKey OPS -Summary 'Minimal' -WhatIf | Out-Null
        Should -Invoke Invoke-PtJiraRequest -ModuleName PowerShellToolbox -Times 0 -Exactly
    }

    It 'rejects labels with spaces' {
        { New-PtJiraIssue -ProjectKey OPS -Summary 'x' -Label 'two words' -Confirm:$false } | Should -Throw
    }
}

Describe 'Add-PtJiraWorklog' {
    BeforeEach {
        Mock Invoke-PtJiraRequest -ModuleName PowerShellToolbox { [pscustomobject]@{ id = '777'; timeSpent = '1h 30m'; started = '2022-05-22T09:00:00.000+0200' } }
    }

    It 'sends the time and the start in the format Jira wants' {
        $started = [datetimeoffset]::new(2022, 5, 22, 9, 0, 0, [timespan]::FromHours(2))
        $result = Add-PtJiraWorklog -Key OPS-1 -TimeSpent '1h 30m' -Started $started -Comment 'Extended the volume.' -Confirm:$false
        $result.WorklogId | Should -Be '777'
        Should -Invoke Invoke-PtJiraRequest -ModuleName PowerShellToolbox -Times 1 -Exactly -ParameterFilter {
            $Path -eq '/rest/api/3/issue/OPS-1/worklog' -and $Body.timeSpent -eq '1h 30m' -and
            $Body.started -eq '2022-05-22T09:00:00.000+0200' -and $Body.comment.content[0].content[0].text -eq 'Extended the volume.'
        }
    }

    It 'rejects a time that is not in Jira notation' {
        { Add-PtJiraWorklog -Key OPS-1 -TimeSpent '90 minutes' -Confirm:$false } | Should -Throw
        { Add-PtJiraWorklog -Key OPS-1 -TimeSpent '1.5h' -Confirm:$false } | Should -Throw
    }

    It 'does nothing with -WhatIf' {
        Add-PtJiraWorklog -Key OPS-1 -TimeSpent '1h' -WhatIf | Out-Null
        Should -Invoke Invoke-PtJiraRequest -ModuleName PowerShellToolbox -Times 0 -Exactly
    }
}

Describe 'New-PtJql' {
    It 'builds a single condition' {
        New-PtJql -Project OPS | Should -Be 'project = "OPS"'
    }

    It 'turns several values into IN (...)' {
        New-PtJql -Status 'In Progress', 'Open' | Should -Be 'status IN ("In Progress", "Open")'
    }

    It 'joins conditions with AND and sorts' {
        $jql = New-PtJql -Project OPS -NotStatusCategory Done -UpdatedWithinDays 7 -OrderBy updated -Descending
        $jql | Should -Be 'project = "OPS" AND statusCategory != "Done" AND updated >= -7d ORDER BY updated DESC'
    }

    It 'handles unassigned issues, labels, text and dates' {
        $jql = New-PtJql -Unassigned -Label disk, sql -Text 'disk full' -CreatedAfter ([datetime]'2023-05-01')
        $jql | Should -Be 'assignee IS EMPTY AND labels = "disk" AND labels = "sql" AND created >= "2023-05-01" AND text ~ "disk full"'
    }

    It 'escapes quotes and backslashes in values' {
        New-PtJql -Text 'say "hi" \ there' | Should -Be 'text ~ "say \"hi\" \\ there"'
    }

    It 'wraps extra clauses in parentheses' {
        New-PtJql -Project OPS -Clause 'priority = High OR labels = urgent' | Should -Be 'project = "OPS" AND (priority = High OR labels = urgent)'
    }

    It 'gives an empty string when nothing is asked for' {
        New-PtJql | Should -Be ''
    }

    It 'rejects an order-by field that could carry more JQL' {
        { New-PtJql -OrderBy 'updated; DROP' } | Should -Throw
    }
}

Describe 'Add-PtJiraAttachment' {
    BeforeEach {
        Mock Invoke-PtJiraRequest -ModuleName PowerShellToolbox {
            [pscustomobject]@{ id = '20001'; filename = 'report.html'; size = 2048; mimeType = 'text/html' }
        }
        $file = Join-Path $TestDrive 'report.html'
        Set-Content -LiteralPath $file -Value '<html></html>'
    }

    It 'uploads the file with the header Jira requires' {
        $result = Add-PtJiraAttachment -Key OPS-1 -Path $file -Confirm:$false
        $result.AttachmentId | Should -Be '20001'
        $result.SizeKB | Should -Be 2
        Should -Invoke Invoke-PtJiraRequest -ModuleName PowerShellToolbox -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'Post' -and $Path -eq '/rest/api/3/issue/OPS-1/attachments' -and
            $Headers['X-Atlassian-Token'] -eq 'no-check' -and $Form.file.Name -eq 'report.html'
        }
    }

    It 'takes files from the pipeline' {
        Get-Item -LiteralPath $file | Add-PtJiraAttachment -Key OPS-1 -Confirm:$false | Out-Null
        Should -Invoke Invoke-PtJiraRequest -ModuleName PowerShellToolbox -Times 1 -Exactly
    }

    It 'refuses a file that is too large, empty or missing' {
        $big = Join-Path $TestDrive 'big.bin'
        $stream = [System.IO.File]::Create($big)
        $stream.SetLength(2MB)
        $stream.Dispose()
        $empty = Join-Path $TestDrive 'empty.txt'
        New-Item -ItemType File -Path $empty | Out-Null

        { Add-PtJiraAttachment -Key OPS-1 -Path $big -MaxSizeMB 1 -Confirm:$false -ErrorAction Stop } | Should -Throw '*more than the limit*'
        { Add-PtJiraAttachment -Key OPS-1 -Path $empty -Confirm:$false -ErrorAction Stop } | Should -Throw '*empty*'
        { Add-PtJiraAttachment -Key OPS-1 -Path (Join-Path $TestDrive 'nope.txt') -Confirm:$false -ErrorAction Stop } | Should -Throw '*does not exist*'
        Should -Invoke Invoke-PtJiraRequest -ModuleName PowerShellToolbox -Times 0 -Exactly
    }

    It 'uploads nothing with -WhatIf' {
        Add-PtJiraAttachment -Key OPS-1 -Path $file -WhatIf
        Should -Invoke Invoke-PtJiraRequest -ModuleName PowerShellToolbox -Times 0 -Exactly
    }
}

Describe 'ConvertFrom-PtJiraDate' {
    It 'parses Jira timestamps with the offset written without a colon' -ForEach @(
        @{ Text = '2024-08-04T10:11:12.345+0000'; Utc = '2024-08-04 10:11:12.345' },
        @{ Text = '2024-08-04T10:11:12.000+0200'; Utc = '2024-08-04 08:11:12.000' },
        @{ Text = '2024-08-04T10:11:12.000-0530'; Utc = '2024-08-04 15:41:12.000' },
        @{ Text = '2024-08-04T10:11:12.345+00:00'; Utc = '2024-08-04 10:11:12.345' }
    ) {
        $result = InModuleScope PowerShellToolbox -Parameters @{ Text = $Text } { ConvertFrom-PtJiraDate -Text $Text }
        $result.UtcDateTime.ToString('yyyy-MM-dd HH:mm:ss.fff') | Should -Be $Utc
    }

    It 'returns nothing for empty or unreadable text' -ForEach @(
        @{ Text = $null }, @{ Text = '' }, @{ Text = 'yesterday-ish' }
    ) {
        InModuleScope PowerShellToolbox -Parameters @{ Text = $Text } { ConvertFrom-PtJiraDate -Text $Text } | Should -BeNullOrEmpty
    }
}

Describe 'ConvertFrom-PtJiraIssue' {
    It 'copes with missing fields' {
        $flat = InModuleScope PowerShellToolbox {
            ConvertFrom-PtJiraIssue -Issue ([pscustomobject]@{ key = 'OPS-9'; fields = [pscustomobject]@{ summary = 'Only a summary' } }) -BaseUri 'https://example.atlassian.net'
        }
        $flat.Key | Should -Be 'OPS-9'
        $flat.Summary | Should -Be 'Only a summary'
        $flat.Assignee | Should -BeNullOrEmpty
        $flat.Status | Should -BeNullOrEmpty
        $flat.Created | Should -BeNullOrEmpty
        $flat.Url | Should -Be 'https://example.atlassian.net/browse/OPS-9'
    }

    It 'leaves the address out without a base address' {
        $flat = InModuleScope PowerShellToolbox {
            ConvertFrom-PtJiraIssue -Issue ([pscustomobject]@{ key = 'OPS-9'; fields = [pscustomobject]@{ summary = 's' } })
        }
        $flat.Url | Should -BeNullOrEmpty
    }

    It 'flattens several issues from the pipeline' {
        $keys = InModuleScope PowerShellToolbox {
            $issues = 1..3 | ForEach-Object { [pscustomobject]@{ key = "OPS-$_"; fields = [pscustomobject]@{ summary = "s$_" } } }
            ($issues | ConvertFrom-PtJiraIssue).Key -join ','
        }
        $keys | Should -Be 'OPS-1,OPS-2,OPS-3'
    }
}

Describe 'Get-PtJiraIssue' {
    BeforeAll {
        Mock Invoke-PtJiraRequest -ModuleName PowerShellToolbox {
            [pscustomobject]@{
                key    = 'OPS-5'
                fields = [pscustomobject]@{
                    summary     = 'Disk is full'
                    status      = [pscustomobject]@{ name = 'Open'; statusCategory = [pscustomobject]@{ name = 'To Do' } }
                    description = [pscustomobject]@{ type = 'doc'; content = @([pscustomobject]@{ type = 'paragraph'; content = @([pscustomobject]@{ type = 'text'; text = 'F: is at 99 percent' }) }) }
                    labels      = @('disk', 'sql')
                    comment     = [pscustomobject]@{ comments = @(
                            [pscustomobject]@{ author = [pscustomobject]@{ displayName = 'Sam'; accountId = 'abc' }; created = '2024-08-01T09:00:00.000+0000'; body = [pscustomobject]@{ type = 'doc'; content = @([pscustomobject]@{ type = 'paragraph'; content = @([pscustomobject]@{ type = 'text'; text = 'On it.' }) }) } }
                        ) }
                }
            }
        }
        InModuleScope PowerShellToolbox { $script:PtJira = @{ BaseUri = 'https://example.atlassian.net'; Headers = @{} } }
    }

    It 'returns the description as plain text and the labels' {
        $issue = Get-PtJiraIssue OPS-5
        $issue.Description | Should -Be 'F: is at 99 percent'
        $issue.Labels -join ',' | Should -Be 'disk,sql'
        $issue.PSObject.Properties.Name | Should -Not -Contain 'Comments'
    }

    It 'adds the comments on request, and asks for the comment field' {
        $issue = Get-PtJiraIssue OPS-5 -IncludeComments
        $issue.Comments.Count | Should -Be 1
        $issue.Comments[0].Author | Should -Be 'Sam'
        $issue.Comments[0].Text | Should -Be 'On it.'
        Should -Invoke Invoke-PtJiraRequest -ModuleName PowerShellToolbox -ParameterFilter { $Query.fields -match 'comment' }
    }
}
