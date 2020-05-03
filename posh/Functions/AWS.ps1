try {
    if (!$DotFilesFastLoad) {
        Test-ModuleAvailable -Name AWSPowerShell.NetCore, AWSPowerShell -Require Any -Verbose:$false
    }
} catch {
    Write-Verbose -Message (Get-DotFilesMessage -Message 'Skipping import of AWS functions.')
    return
}

Write-Verbose -Message (Get-DotFilesMessage -Message 'Importing AWS functions ...')

#region IAM

# Set AWS credential environment variables from an AWSCredentials object
Function Set-AWSCredentialEnvironment {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', '')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUsePSCredentialType', '')]
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [Amazon.SecurityToken.Model.Credentials]$Credential
    )

    Set-Item -Path Env:\AWS_ACCESS_KEY_ID -Value $Credential.AccessKeyId
    Set-Item -Path Env:\AWS_SECRET_ACCESS_KEY -Value $Credential.SecretAccessKey
    Set-Item -Path Env:\AWS_SESSION_TOKEN -Value $Credential.SessionToken
}

#endregion

#region Route 53

Function Set-R53HostedZoneParkedRecords {
    [CmdletBinding(SupportsShouldProcess)]
    Param(
        [Parameter(Mandatory)]
        [String[]]$Domain,

        [Parameter(Mandatory)]
        [ValidateSet('MX', 'SPF', 'DKIM', 'DMARC', 'CAA', 'Redirect')]
        [String[]]$Records,

        # E.g. mailto:dmarc-rua@domain.com
        [ValidateNotNullOrEmpty()]
        [String[]]$DmarcRua,
        # E.g. mailto:dmarc-ruf@domain.com
        [ValidateNotNullOrEmpty()]
        [String[]]$DmarcRuf,

        # E.g. amazon.com
        [ValidateNotNullOrEmpty()]
        [String[]]$CaaIssue,
        # E.g. digicert.com
        [ValidateNotNullOrEmpty()]
        [String[]]$CaaIssueWild,
        # E.g. mailto:netops@domain.com
        [ValidateNotNullOrEmpty()]
        [String[]]$CaaIoDef,

        # E.g. 1234567890ABCD.cloudfront.net.
        [ValidateNotNullOrEmpty()]
        [String]$RedirectCloudFrontDomainName,
        [ValidateSet('A', 'AAAA')]
        [String[]]$RedirectCloudFrontRecordTypes='A'
    )

    Test-ModuleAvailable -Name AWSPowerShell.NetCore, AWSPowerShell -Require Any

    try {
        $Zones = Get-R53HostedZones -ErrorAction Stop
    } catch {
        throw $_
    }

    $CloudFrontHostedZoneId = 'Z2FDTNDATAQYW2'
    $Changes = [Collections.ArrayList]::new()

    # Construct the DMARC record
    if ($Records -contains 'DMARC') {
        $Dmarc = 'v=DMARC1; p=reject'

        if ($DmarcRua) {
            $Dmarc = '{0}; rua={1}' -f $Dmarc, [String]::Join(',', $DmarcRua)
        }

        if ($DmarcRuf) {
            $Dmarc = '{0}; ruf={1}' -f $Dmarc, [String]::Join(',', $DmarcRuf)
        }

        $Dmarc = '{0}; fo=1' -f $Dmarc
    }

    # Construct each CAA record
    if ($Records -contains 'CAA') {
        $Caa = [Collections.ArrayList]::new()

        if ($CaaIssue) {
            foreach ($CaaIssuer in $CaaIssue) {
                $null = $Caa.Add(('0 issue "{0}"' -f $CaaIssuer))
            }
        } else {
            $null = $Caa.Add('0 issue ";"')
        }

        if ($CaaIssueWild) {
            foreach ($CaaWildIssuer in $CaaIssueWild) {
                $null = $Caa.Add(('0 issuewild "{0}"' -f $CaaWildIssuer))
            }
        } elseif ($CaaIssue) {
            $null = $Caa.Add('0 issuewild ";"')
        }

        if ($CaaIoDef) {
            foreach ($CaaReportUrl in $CaaIoDef) {
                $null = $Caa.Add(('0 iodef "{0}"' -f $CaaReportUrl))
            }
        }
    }

    # Process record changes for each zone
    foreach ($ZoneName in $Domain) {
        $ZoneName = $ZoneName.TrimEnd('.').ToLower()
        $ZoneFqdn = '{0}.' -f $ZoneName

        $Zone = $Zones | Where-Object Name -eq $ZoneFqdn
        if (!$Zone) {
            Write-Warning -Message ('Unable to set records for non-existent zone: {0}' -f $ZoneName)
            continue
        }

        $ZoneRecords = [Collections.ArrayList]::new()

        if ($Records -contains 'MX') {
            $Record = New-Object Amazon.Route53.Model.Change
            $Record.Action = 'UPSERT'
            $Record.ResourceRecordSet = New-Object Amazon.Route53.Model.ResourceRecordSet
            $Record.ResourceRecordSet.Name = $ZoneName
            $Record.ResourceRecordSet.Type = 'MX'
            $Record.ResourceRecordSet.TTL = 3600
            $Record.ResourceRecordSet.ResourceRecords.Add(@{ Value = '0 .' })
            $null = $ZoneRecords.Add($Record)
        }

        if ($Records -contains 'SPF') {
            $Record = New-Object Amazon.Route53.Model.Change
            $Record.Action = 'UPSERT'
            $Record.ResourceRecordSet = New-Object Amazon.Route53.Model.ResourceRecordSet
            $Record.ResourceRecordSet.Name = $ZoneName
            $Record.ResourceRecordSet.Type = 'TXT'
            $Record.ResourceRecordSet.TTL = 3600
            $Record.ResourceRecordSet.ResourceRecords.Add(@{ Value = '"v=spf1 -all"' })
            $null = $ZoneRecords.Add($Record)
        }

        if ($Records -contains 'DKIM') {
            $Record = New-Object Amazon.Route53.Model.Change
            $Record.Action = 'UPSERT'
            $Record.ResourceRecordSet = New-Object Amazon.Route53.Model.ResourceRecordSet
            $Record.ResourceRecordSet.Name = ('*._domainkey.{0}' -f $ZoneName)
            $Record.ResourceRecordSet.Type = 'TXT'
            $Record.ResourceRecordSet.TTL = 3600
            $Record.ResourceRecordSet.ResourceRecords.Add(@{ Value = '"v=DKIM1; p="' })
            $null = $ZoneRecords.Add($Record)
        }

        if ($Records -contains 'DMARC') {
            $Record = New-Object Amazon.Route53.Model.Change
            $Record.Action = 'UPSERT'
            $Record.ResourceRecordSet = New-Object Amazon.Route53.Model.ResourceRecordSet
            $Record.ResourceRecordSet.Name = ('_dmarc.{0}' -f $ZoneName)
            $Record.ResourceRecordSet.Type = 'TXT'
            $Record.ResourceRecordSet.TTL = 3600
            $Record.ResourceRecordSet.ResourceRecords.Add(@{ Value = ('"{0}"' -f $Dmarc) })
            $null = $ZoneRecords.Add($Record)
        }

        if ($Caa) {
            $Record = New-Object Amazon.Route53.Model.Change
            $Record.Action = 'UPSERT'
            $Record.ResourceRecordSet = New-Object Amazon.Route53.Model.ResourceRecordSet
            $Record.ResourceRecordSet.Name = $ZoneName
            $Record.ResourceRecordSet.Type = 'CAA'
            $Record.ResourceRecordSet.TTL = 900

            foreach ($Entry in $Caa) {
                $Record.ResourceRecordSet.ResourceRecords.Add(@{ Value = $Entry })
            }

            $null = $ZoneRecords.Add($Record)
        }

        if ($RedirectCloudFrontDomainName) {
            foreach ($RecordName in @($ZoneName, ('*.{0}' -f $ZoneName))) {
                foreach ($RecordType in $RedirectCloudFrontRecordTypes) {
                    $Record = New-Object Amazon.Route53.Model.Change
                    $Record.Action = 'UPSERT'
                    $Record.ResourceRecordSet = New-Object Amazon.Route53.Model.ResourceRecordSet
                    $Record.ResourceRecordSet.Name = $RecordName
                    $Record.ResourceRecordSet.Type = $RecordType
                    $Record.ResourceRecordSet.AliasTarget = New-Object Amazon.Route53.Model.AliasTarget
                    $Record.ResourceRecordSet.AliasTarget.HostedZoneId = $CloudFrontHostedZoneId
                    $Record.ResourceRecordSet.AliasTarget.DNSName = $RedirectCloudFrontDomainName
                    $Record.ResourceRecordSet.AliasTarget.EvaluateTargetHealth = $false
                    $null = $ZoneRecords.Add($Record)
                }
            }
        }

        $ZoneId = $Zone.Id.TrimStart('/hostedzone/')
        if ($PSCmdlet.ShouldProcess($ZoneName, 'Set records')) {
            Write-Verbose -Message ('Setting records for Route 53 zone: {0}' -f $ZoneName)
            $Result = Edit-R53ResourceRecordSet -HostedZoneId $ZoneId -ChangeBatch_Change $ZoneRecords -ChangeBatch_Comment $ZoneName
            $null = $Changes.Add($Result)
        }
    }

    return $Changes
}

#endregion
