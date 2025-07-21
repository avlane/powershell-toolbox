#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

# Pester 5 tests for the REST helpers. No network: Invoke-RestMethod,
# Invoke-WebRequest and Start-Sleep are mocked.

BeforeAll {
    $manifest = Join-Path (Join-Path (Split-Path -Parent $PSScriptRoot) 'PowerShellToolbox') 'PowerShellToolbox.psd1'
    Import-Module $manifest -Force
}

Describe 'Invoke-PtRestRetry' {
    BeforeEach {
        $global:PtTestCalls = 0
        Mock Start-Sleep -ModuleName PowerShellToolbox { }
        # 0.25 is the middle of the jitter range, so the delays come out unchanged
        Mock Get-Random -ModuleName PowerShellToolbox { 0.25 }
    }

    AfterAll {
        Remove-Variable -Name PtTestCalls -Scope Global -ErrorAction SilentlyContinue
    }

    It 'returns the result of a call that works' {
        Mock Invoke-RestMethod -ModuleName PowerShellToolbox { 'fine' }
        Invoke-PtRestRetry -Uri 'https://api.example.com/x' | Should -Be 'fine'
        Should -Invoke Invoke-RestMethod -ModuleName PowerShellToolbox -Times 1 -Exactly
        Should -Invoke Start-Sleep -ModuleName PowerShellToolbox -Times 0 -Exactly
    }

    It 'retries a 503 with growing delays and then succeeds' {
        Mock Invoke-RestMethod -ModuleName PowerShellToolbox {
            $global:PtTestCalls++
            if ($global:PtTestCalls -lt 3) { throw 'service unavailable' }
            'recovered'
        }
        Mock Get-PtHttpErrorDetail -ModuleName PowerShellToolbox {
            [pscustomobject]@{ StatusCode = 503; RetryAfter = $null; IsNetworkError = $false; Message = 'busy' }
        }
        Invoke-PtRestRetry -Uri 'https://api.example.com/x' | Should -Be 'recovered'
        Should -Invoke Invoke-RestMethod -ModuleName PowerShellToolbox -Times 3 -Exactly
        Should -Invoke Start-Sleep -ModuleName PowerShellToolbox -Times 1 -Exactly -ParameterFilter { $Seconds -eq 2 }
        Should -Invoke Start-Sleep -ModuleName PowerShellToolbox -Times 1 -Exactly -ParameterFilter { $Seconds -eq 4 }
    }

    It 'stops waiting when the next delay would pass the total budget' {
        Mock Invoke-RestMethod -ModuleName PowerShellToolbox { $global:PtTestCalls++; throw 'busy' }
        Mock Get-PtHttpErrorDetail -ModuleName PowerShellToolbox {
            [pscustomobject]@{ StatusCode = 429; RetryAfter = '40'; IsNetworkError = $false; Message = 'slow down' }
        }
        { Invoke-PtRestRetry -Uri 'https://api.example.com/x' -MaxRetries 5 -MaxTotalDelaySeconds 100 } | Should -Throw '*busy*'
        # 40 + 40 fits into 100, a third 40 does not
        Should -Invoke Start-Sleep -ModuleName PowerShellToolbox -Times 2 -Exactly
        Should -Invoke Invoke-RestMethod -ModuleName PowerShellToolbox -Times 3 -Exactly
    }

    It 'does not limit the waiting without a budget' {
        Mock Invoke-RestMethod -ModuleName PowerShellToolbox { $global:PtTestCalls++; throw 'busy' }
        Mock Get-PtHttpErrorDetail -ModuleName PowerShellToolbox {
            [pscustomobject]@{ StatusCode = 429; RetryAfter = '40'; IsNetworkError = $false; Message = 'slow down' }
        }
        { Invoke-PtRestRetry -Uri 'https://api.example.com/x' -MaxRetries 3 } | Should -Throw
        Should -Invoke Start-Sleep -ModuleName PowerShellToolbox -Times 3 -Exactly
    }

    It 'varies the back-off by up to a quarter either way' {
        Mock Invoke-RestMethod -ModuleName PowerShellToolbox { $global:PtTestCalls++; throw 'busy' }
        Mock Get-PtHttpErrorDetail -ModuleName PowerShellToolbox {
            [pscustomobject]@{ StatusCode = 503; RetryAfter = $null; IsNetworkError = $false; Message = 'busy' }
        }
        Mock Get-Random -ModuleName PowerShellToolbox { 0.0 }
        { Invoke-PtRestRetry -Uri 'https://api.example.com/x' -MaxRetries 1 } | Should -Throw
        Should -Invoke Start-Sleep -ModuleName PowerShellToolbox -Times 1 -Exactly -ParameterFilter { $Seconds -eq 1.5 }
    }

    It 'leaves the back-off alone with -NoJitter' {
        Mock Invoke-RestMethod -ModuleName PowerShellToolbox { $global:PtTestCalls++; throw 'busy' }
        Mock Get-PtHttpErrorDetail -ModuleName PowerShellToolbox {
            [pscustomobject]@{ StatusCode = 503; RetryAfter = $null; IsNetworkError = $false; Message = 'busy' }
        }
        Mock Get-Random -ModuleName PowerShellToolbox { 0.0 }
        { Invoke-PtRestRetry -Uri 'https://api.example.com/x' -MaxRetries 1 -NoJitter } | Should -Throw
        Should -Invoke Start-Sleep -ModuleName PowerShellToolbox -Times 1 -Exactly -ParameterFilter { $Seconds -eq 2 }
    }

    It 'waits as long as Retry-After says' {
        Mock Invoke-RestMethod -ModuleName PowerShellToolbox {
            $global:PtTestCalls++
            if ($global:PtTestCalls -lt 2) { throw 'too many requests' }
            'ok'
        }
        Mock Get-PtHttpErrorDetail -ModuleName PowerShellToolbox {
            [pscustomobject]@{ StatusCode = 429; RetryAfter = '7'; IsNetworkError = $false; Message = 'slow down' }
        }
        Invoke-PtRestRetry -Uri 'https://api.example.com/x' | Should -Be 'ok'
        Should -Invoke Start-Sleep -ModuleName PowerShellToolbox -Times 1 -Exactly -ParameterFilter { $Seconds -eq 7 }
    }

    It 'waits until the date in an HTTP-date Retry-After' {
        Mock Invoke-RestMethod -ModuleName PowerShellToolbox {
            $global:PtTestCalls++
            if ($global:PtTestCalls -lt 2) { throw 'too many requests' }
            'ok'
        }
        Mock Get-PtHttpErrorDetail -ModuleName PowerShellToolbox {
            [pscustomobject]@{ StatusCode = 429; RetryAfter = [datetimeoffset]::UtcNow.AddSeconds(30).ToString('r'); IsNetworkError = $false; Message = 'slow down' }
        }
        Invoke-PtRestRetry -Uri 'https://api.example.com/x' | Should -Be 'ok'
        Should -Invoke Start-Sleep -ModuleName PowerShellToolbox -Times 1 -Exactly -ParameterFilter { $Seconds -ge 28 -and $Seconds -le 31 }
    }

    It 'retries network errors' {
        Mock Invoke-RestMethod -ModuleName PowerShellToolbox {
            $global:PtTestCalls++
            if ($global:PtTestCalls -lt 2) { throw 'connection closed' }
            'back'
        }
        Mock Get-PtHttpErrorDetail -ModuleName PowerShellToolbox {
            [pscustomobject]@{ StatusCode = $null; RetryAfter = $null; IsNetworkError = $true; Message = 'closed' }
        }
        Invoke-PtRestRetry -Uri 'https://api.example.com/x' | Should -Be 'back'
    }

    It 'does not retry errors that trying again cannot fix' {
        Mock Invoke-RestMethod -ModuleName PowerShellToolbox { $global:PtTestCalls++; throw 'not found' }
        Mock Get-PtHttpErrorDetail -ModuleName PowerShellToolbox {
            [pscustomobject]@{ StatusCode = 404; RetryAfter = $null; IsNetworkError = $false; Message = 'not found' }
        }
        { Invoke-PtRestRetry -Uri 'https://api.example.com/x' } | Should -Throw '*not found*'
        Should -Invoke Invoke-RestMethod -ModuleName PowerShellToolbox -Times 1 -Exactly
    }

    It 'gives up after MaxRetries retries' {
        Mock Invoke-RestMethod -ModuleName PowerShellToolbox { $global:PtTestCalls++; throw 'server error' }
        Mock Get-PtHttpErrorDetail -ModuleName PowerShellToolbox {
            [pscustomobject]@{ StatusCode = 500; RetryAfter = $null; IsNetworkError = $false; Message = 'server error' }
        }
        { Invoke-PtRestRetry -Uri 'https://api.example.com/x' -MaxRetries 2 } | Should -Throw '*server error*'
        Should -Invoke Invoke-RestMethod -ModuleName PowerShellToolbox -Times 3 -Exactly
    }

    It 'sends objects as JSON' {
        Mock Invoke-RestMethod -ModuleName PowerShellToolbox { 'sent' }
        Invoke-PtRestRetry -Uri 'https://api.example.com/x' -Method Post -Body @{ name = 'a' } | Out-Null
        Should -Invoke Invoke-RestMethod -ModuleName PowerShellToolbox -Times 1 -Exactly -ParameterFilter {
            $ContentType -eq 'application/json' -and $Body -match '"name":\s*"a"'
        }
    }
}

Describe 'Invoke-PtRestRetry with HTTP error responses' {
    BeforeEach {
        $global:PtTestCalls = 0
        Mock Start-Sleep -ModuleName PowerShellToolbox { }
    }

    AfterAll {
        Remove-Variable -Name PtTestCalls -Scope Global -ErrorAction SilentlyContinue
    }

    It 'retries an error response that did not throw, honouring Retry-After' {
        Mock Invoke-WebRequest -ModuleName PowerShellToolbox {
            $global:PtTestCalls++
            if ($global:PtTestCalls -lt 2) {
                [pscustomobject]@{ StatusCode = 503; Headers = @{ 'Retry-After' = @('3') }; Content = 'busy' }
            }
            else {
                [pscustomobject]@{ StatusCode = 200; Headers = @{}; Content = '{}' }
            }
        }
        $response = Invoke-PtRestRetry -Uri 'https://api.example.com/x' -Raw
        $response.StatusCode | Should -Be 200
        Should -Invoke Invoke-WebRequest -ModuleName PowerShellToolbox -Times 2 -Exactly
        Should -Invoke Start-Sleep -ModuleName PowerShellToolbox -Times 1 -Exactly -ParameterFilter { $Seconds -eq 3 }
    }

    It 'throws the status and body of an error that is not worth retrying' {
        Mock Invoke-WebRequest -ModuleName PowerShellToolbox {
            [pscustomobject]@{ StatusCode = 404; Headers = @{}; Content = 'no such thing' }
        }
        { Invoke-PtRestRetry -Uri 'https://api.example.com/x' -Raw } | Should -Throw '*HTTP 404*no such thing*'
        Should -Invoke Invoke-WebRequest -ModuleName PowerShellToolbox -Times 1 -Exactly
    }

    It 'asks PowerShell not to throw on HTTP errors' {
        Mock Invoke-WebRequest -ModuleName PowerShellToolbox { [pscustomobject]@{ StatusCode = 200; Headers = @{}; Content = '' } }
        Invoke-PtRestRetry -Uri 'https://api.example.com/x' -Raw | Out-Null
        Should -Invoke Invoke-WebRequest -ModuleName PowerShellToolbox -Times 1 -Exactly -ParameterFilter { $SkipHttpErrorCheck -eq $true }
    }
}

Describe 'Get-PtHttpErrorDetail' {
    It 'recognises connection failures as network errors' {
        $detail = InModuleScope PowerShellToolbox {
            $exception = New-Object -TypeName System.Net.Http.HttpRequestException -ArgumentList 'Connection refused'
            $record = New-Object -TypeName System.Management.Automation.ErrorRecord -ArgumentList $exception, 'ConnectFailure', ([System.Management.Automation.ErrorCategory]::ConnectionError), $null
            Get-PtHttpErrorDetail -ErrorRecord $record
        }
        $detail.IsNetworkError | Should -Be $true
        $detail.StatusCode | Should -BeNullOrEmpty
        $detail.Message | Should -Be 'Connection refused'
    }

    It 'does not call other exceptions network errors' {
        $detail = InModuleScope PowerShellToolbox {
            $exception = New-Object -TypeName System.ArgumentException -ArgumentList 'bad argument'
            $record = New-Object -TypeName System.Management.Automation.ErrorRecord -ArgumentList $exception, 'Bad', ([System.Management.Automation.ErrorCategory]::InvalidArgument), $null
            Get-PtHttpErrorDetail -ErrorRecord $record
        }
        $detail.IsNetworkError | Should -Be $false
    }

    It 'reads the status and Retry-After from an exception that carries a response' {
        $detail = InModuleScope PowerShellToolbox {
            $headers = New-Object -TypeName psobject
            $headers | Add-Member -MemberType ScriptMethod -Name TryGetValues -Value { param($name, [ref]$values) $values.Value = @('9'); $true }
            $exception = New-Object -TypeName System.Exception -ArgumentList 'Too many requests'
            $exception | Add-Member -NotePropertyName Response -NotePropertyValue ([pscustomobject]@{ StatusCode = 429; Headers = $headers })
            $record = New-Object -TypeName System.Management.Automation.ErrorRecord -ArgumentList $exception, 'Http429', ([System.Management.Automation.ErrorCategory]::LimitsExceeded), $null
            Get-PtHttpErrorDetail -ErrorRecord $record
        }
        $detail.StatusCode | Should -Be 429
        $detail.RetryAfter | Should -Be '9'
        $detail.IsNetworkError | Should -Be $false
    }
}

Describe 'ConvertFrom-PtRetryAfter' {
    It 'understands seconds and HTTP dates' -ForEach @(
        @{ Value = '120'; Expected = 120 },
        @{ Value = ' 7 '; Expected = 7 },
        @{ Value = 'Wed, 21 Oct 2015 07:28:30 GMT'; Expected = 30 },
        @{ Value = 'Wed, 21 Oct 2015 07:20:00 GMT'; Expected = 0 },
        @{ Value = '99999'; Expected = 300 },
        @{ Value = 'Thu, 22 Oct 2015 07:28:00 GMT'; Expected = 300 },
        @{ Value = 'soon'; Expected = $null },
        @{ Value = ''; Expected = $null }
    ) {
        $result = InModuleScope PowerShellToolbox -Parameters @{ Value = $Value } {
            ConvertFrom-PtRetryAfter -Value $Value -Now ([datetimeoffset]::new(2015, 10, 21, 7, 28, 0, [timespan]::Zero))
        }
        $result | Should -Be $Expected
    }
}

Describe 'Get-PtNextLink' {
    It 'finds the next page among several relations' {
        $result = InModuleScope PowerShellToolbox {
            Get-PtNextLink -LinkHeader '<https://api.example.com/items?page=1>; rel="prev", <https://api.example.com/items?page=3>; rel="next", <https://api.example.com/items?page=9>; rel="last"'
        }
        $result | Should -Be 'https://api.example.com/items?page=3'
    }

    It 'returns nothing on the last page' {
        $result = InModuleScope PowerShellToolbox {
            Get-PtNextLink -LinkHeader '<https://api.example.com/items?page=1>; rel="first", <https://api.example.com/items?page=8>; rel="prev"'
        }
        $result | Should -BeNullOrEmpty
    }

    It 'copes with no header at all' {
        InModuleScope PowerShellToolbox { Get-PtNextLink -LinkHeader $null } | Should -BeNullOrEmpty
    }
}

Describe 'Invoke-PtRestPaged' {
    Context 'following a property of the body' {
        BeforeAll {
            Mock Invoke-PtRestRetry -ModuleName PowerShellToolbox -ParameterFilter { $Uri -eq 'https://graph.example.com/users' } {
                [pscustomobject]@{ value = @('a', 'b'); nextLink = 'https://graph.example.com/users?page=2' }
            }
            Mock Invoke-PtRestRetry -ModuleName PowerShellToolbox -ParameterFilter { $Uri -eq 'https://graph.example.com/users?page=2' } {
                [pscustomobject]@{ value = @('c'); nextLink = $null }
            }
            $items = @(Invoke-PtRestPaged -Uri 'https://graph.example.com/users' -ItemsProperty value -NextLinkProperty nextLink)
        }

        It 'returns the items of all pages' {
            $items -join ',' | Should -Be 'a,b,c'
        }

        It 'fetched exactly two pages' {
            Should -Invoke Invoke-PtRestRetry -ModuleName PowerShellToolbox -Times 2 -Exactly
        }
    }

    Context 'following the Link header' {
        BeforeAll {
            Mock Invoke-PtRestRetry -ModuleName PowerShellToolbox -ParameterFilter { $Uri -eq 'https://api.example.com/repos' } {
                [pscustomobject]@{ Content = '[{"name":"one"},{"name":"two"}]'; Headers = @{ Link = '<https://api.example.com/repos?page=2>; rel="next"' } }
            }
            Mock Invoke-PtRestRetry -ModuleName PowerShellToolbox -ParameterFilter { $Uri -eq 'https://api.example.com/repos?page=2' } {
                [pscustomobject]@{ Content = '[{"name":"three"}]'; Headers = @{} }
            }
            $items = @(Invoke-PtRestPaged -Uri 'https://api.example.com/repos' -UseLinkHeader)
        }

        It 'returns the items of both pages' {
            $items.name -join ',' | Should -Be 'one,two,three'
        }
    }

    Context 'paging by offset' {
        BeforeAll {
            Mock Invoke-PtRestRetry -ModuleName PowerShellToolbox -ParameterFilter { $Uri -eq 'https://api.example.com/items?offset=0&limit=2' } {
                [pscustomobject]@{ items = @('a', 'b') }
            }
            Mock Invoke-PtRestRetry -ModuleName PowerShellToolbox -ParameterFilter { $Uri -eq 'https://api.example.com/items?offset=2&limit=2' } {
                [pscustomobject]@{ items = @('c', 'd') }
            }
            Mock Invoke-PtRestRetry -ModuleName PowerShellToolbox -ParameterFilter { $Uri -eq 'https://api.example.com/items?offset=4&limit=2' } {
                [pscustomobject]@{ items = @('e') }
            }
        }

        It 'advances the offset by the number of items and stops at a short page' {
            $items = @(Invoke-PtRestPaged -Uri 'https://api.example.com/items' -ItemsProperty items -OffsetParameter offset -LimitParameter limit -PageSize 2)
            $items -join ',' | Should -Be 'a,b,c,d,e'
            Should -Invoke Invoke-PtRestRetry -ModuleName PowerShellToolbox -Times 3 -Exactly
        }
    }

    Context 'paging by page number' {
        BeforeAll {
            Mock Invoke-PtRestRetry -ModuleName PowerShellToolbox -ParameterFilter { $Uri -eq 'https://api.example.com/items?type=x&page=1&per_page=3' } {
                @('a', 'b', 'c')
            }
            Mock Invoke-PtRestRetry -ModuleName PowerShellToolbox -ParameterFilter { $Uri -eq 'https://api.example.com/items?type=x&page=2&per_page=3' } {
                @('d')
            }
        }

        It 'starts at page 1 and adds to an existing query string' {
            $items = @(Invoke-PtRestPaged -Uri 'https://api.example.com/items?type=x' -OffsetParameter page -LimitParameter per_page -PageSize 3 -PageBased)
            $items -join ',' | Should -Be 'a,b,c,d'
        }
    }

    Context 'safety' {
        It 'stops at MaxPages' {
            Mock Invoke-PtRestRetry -ModuleName PowerShellToolbox {
                [pscustomobject]@{ value = @(1); nextLink = 'https://api.example.com/loop' }
            }
            $items = @(Invoke-PtRestPaged -Uri 'https://api.example.com/loop' -ItemsProperty value -NextLinkProperty nextLink -MaxPages 3 -WarningAction SilentlyContinue)
            $items.Count | Should -Be 3
        }

        It 'needs to know how to find the next page' {
            { Invoke-PtRestPaged -Uri 'https://api.example.com/x' } | Should -Throw '*Say how to find the next page*'
            { Invoke-PtRestPaged -Uri 'https://api.example.com/x' -UseLinkHeader -NextLinkProperty next } | Should -Throw '*only one of*'
            { Invoke-PtRestPaged -Uri 'https://api.example.com/x' -UseLinkHeader -OffsetParameter offset } | Should -Throw '*only one of*'
        }
    }
}
