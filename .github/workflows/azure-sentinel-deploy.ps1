function AttemptAzLogin($psCredential, $tenantId, $cloudEnv) {
    $maxLoginRetries = 3
    $delayInSeconds = 30
    $retryCount = 1
    $stopTrying = $false
    do {
        try {
            Connect-AzAccount -ServicePrincipal -Tenant $tenantId -Credential $psCredential -Environment $cloudEnv | out-null;
            Write-Host "Login Successful"
            $stopTrying = $true
        }
        catch {
            if ($retryCount -ge $maxLoginRetries) {
                Write-Host "Login failed after $maxLoginRetries attempts."
                $stopTrying = $true
            }
            else {
                Write-Host "Login attempt failed, retrying in $delayInSeconds seconds."
                Start-Sleep -Seconds $delayInSeconds
                $retryCount++
            }
        }
    }
    while (-not $stopTrying)
}

function ConnectAzCloud {
    $RawCreds = $Env:creds | ConvertFrom-Json

    Clear-AzContext -Scope Process;
    Clear-AzContext -Scope CurrentUser -Force -ErrorAction SilentlyContinue;
    
    Add-AzEnvironment `
        -Name $Env:cloudEnv `
        -ActiveDirectoryEndpoint $RawCreds.activeDirectoryEndpointUrl `
        -ResourceManagerEndpoint $RawCreds.resourceManagerEndpointUrl `
        -ActiveDirectoryServiceEndpointResourceId $RawCreds.activeDirectoryServiceEndpointResourceId `
        -GraphEndpoint $RawCreds.graphEndpointUrl | out-null;

    $servicePrincipalKey = ConvertTo-SecureString $RawCreds.clientSecret.replace("'", "''") -AsPlainText -Force
    $psCredential = New-Object System.Management.Automation.PSCredential($RawCreds.clientId, $servicePrincipalKey)

    AttemptAzLogin $psCredential $RawCreds.tenantId $Env:cloudEnv
    Set-AzContext -Tenant $RawCreds.tenantId | out-null;
}

function IsValidTemplate($path) {
    Try {
        Test-AzResourceGroupDeployment -ResourceGroupName $Env:resourceGroupName -TemplateFile $path -workspace $Env:workspaceName
        return $true
    }
    Catch {
        Write-Host "[Warning] The file $path is not valid: $_"
        return $false
    }
}

if ($Env:cloudEnv -ne 'AzureCloud') {
    Write-Output "Attempting Sign In to Azure Cloud"
    ConnectAzCloud
}

Write-Output "Starting Deployment for Files in path: $Env:directory"

if (Test-Path -Path $Env:directory) {
    $totalFiles = 0;
    $totalFailed = 0;
    Get-ChildItem -Path $Env:directory -Recurse -Filter *.json |
    ForEach-Object {
        $CurrentFile = $_.FullName
        $totalFiles ++
        $isValid = IsValidTemplate $CurrentFile
        if (-not $isValid) {
            $totalFailed++
            return
        }
        Try {
            New-AzResourceGroupDeployment -ResourceGroupName $Env:resourceGroupName -TemplateFile $CurrentFile -workspace $Env:workspaceName
        }
        Catch {        
            $totalFailed++
            Write-Output "[Warning] Failed to deploy $CurrentFile with error: $_"
        }
    }
    if ($totalFiles -gt 0 -and $totalFailed -gt 0) {
        $error = "$totalFailed of $totalFiles deployments failed."
        Throw $error
    }
}
else {
    Write-Output "[Warning] $Env:directory not found. nothing to deploy"
}