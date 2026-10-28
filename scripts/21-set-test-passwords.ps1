<#
.SYNOPSIS
    Sets a known password on a few named lab accounts so you can sign in as them and test the Entra sign-in experience.

.DESCRIPTION
    The 20 lab users have random passwords that nobody knows, so none of them can be used to sign in. This script resets the
    password of the accounts listed in the CONFIGURATION block to a value you pass in when you run it. In dry-run mode it only
    reports what it would do and needs no password. In real mode it resets each password and turns off "change password at
    next sign-in" so you can sign in straight away.

.NOTES
    LAB: Lab 4, identity and access management (domain iamlab.local). Runs on DC01, after the Entra Cloud Sync step.

    RULES THIS SCRIPT FOLLOWS
    - DRY RUN IS THE DEFAULT. Set $dryRun to $false deliberately.
    - The password is never written in this file and never printed. You pass it in when you run the script.
    - It only touches the accounts you name, and only if they exist, are enabled and sit under the Staff OU.
    - If the password breaks the password policy, that account is reported as FAILED and nothing else is affected.

    KNOWLEDGE
    - Password hash sync copies a hash of the on-premises password to Entra ID, so the same password then works for the
      cloud sign-in. A reset on the domain controller reaches Entra after about two minutes.
    - The password policy still applies. The baseline needs 12 characters. IT users (member of SG-IT) need 16, because of
      the fine-grained policy. The generated password in HOW TO RUN is 20 characters, so it passes both.
    - LAB SHORTCUT. In a real environment an admin does not set a known password for someone else. The user resets their own
      through self-service password reset, or an admin issues a one-time password that must be changed at first sign-in.

    PITFALLS
    - The password travels on the az command line, so treat it as visible to anyone who can read this VM's run-command
      history. Use a throwaway value and never reuse a real password.
    - If you sign in before the two-minute sync finishes, Entra rejects the password. Wait and try again.
    - Do not give this script a mandatory parameter. run-command cannot prompt, so it would hang until it times out.

    EXPECTED OUTPUT
    Dry run: "DRY RUN: would set a new password". Real run: "Password set" for each account.
#>
param([string]$TestPassword = "")

# ===================== CONFIGURATION: CHANGE THESE FOR YOUR ENVIRONMENT =====================
$dryRun   = $true                                          # CHANGE: $true = report only. Set $false to make the changes.
$domainDN = (Get-ADDomain).DistinguishedName               # CHANGE: leave as is to use the current domain.
$staffOU  = "Staff"                                        # CHANGE: the top OU that holds the users. Accounts elsewhere are skipped.
$accounts = @("mjohnson", "ohaddad")                       # CHANGE: the accounts you will sign in as. Keep this list short.
# ============================================================================================

Import-Module ActiveDirectory

if (-not $dryRun -and [string]::IsNullOrEmpty($TestPassword)) {
    "STOPPED: no password supplied. Pass one with --parameters TestPassword=... (see HOW TO RUN). Nothing was changed."
    return
}

$results = @()

foreach ($name in $accounts) {
    $user = Get-ADUser -Filter "SamAccountName -eq '$name'"

    if (-not $user) {
        $results += [pscustomobject]@{ Username = $name; Result = "Skipped (not found)" }
        continue
    }
    if (-not $user.Enabled) {
        $results += [pscustomobject]@{ Username = $name; Result = "Skipped (account is disabled)" }
        continue
    }
    if ($user.DistinguishedName -notlike "*OU=$staffOU,$domainDN") {
        $results += [pscustomobject]@{ Username = $name; Result = "Skipped (not under OU=$staffOU)" }
        continue
    }

    if ($dryRun) {
        $results += [pscustomobject]@{ Username = $name; Result = "DRY RUN: would set a new password" }
        continue
    }

    try {
        $secure = ConvertTo-SecureString $TestPassword -AsPlainText -Force
        Set-ADAccountPassword -Identity $user.DistinguishedName -Reset -NewPassword $secure
        Set-ADUser -Identity $user.DistinguishedName -ChangePasswordAtLogon $false
        $results += [pscustomobject]@{ Username = $name; Result = "Password set" }
    }
    catch {
        $results += [pscustomobject]@{ Username = $name; Result = "FAILED: $($_.Exception.Message)" }
    }
}

$results | Format-Table -AutoSize | Out-String -Width 200

# ===================== HOW TO RUN =====================
# LAB (Azure virtual machine, from your laptop, inside the scripts folder):
#   az login
#   Dry run first (default, no password needed):
#   az vm run-command invoke -g rg-iamlab -n DC01 --command-id RunPowerShellScript --scripts "@21-set-test-passwords.ps1" --query "value[0].message" -o tsv
#   Then make a password on your laptop. It goes to your clipboard and is never printed:
#   $pw = -join ((48..57)+(65..90)+(97..122) | Get-Random -Count 16 | ForEach-Object {[char]$_}); $pw += '-9aZ'
#   Set-Clipboard $pw
#   Change $dryRun to $false in the CONFIGURATION block, then run:
#   az vm run-command invoke -g rg-iamlab -n DC01 --command-id RunPowerShellScript --scripts "@21-set-test-passwords.ps1" --parameters "TestPassword=$pw" --query "value[0].message" -o tsv
#   When you have finished signing in:  Clear-LabClipboard
# ANOTHER ENVIRONMENT: do not use this script. Let users reset their own passwords.
# TO VERIFY: Get-ADUser -Identity <name> -Properties PasswordLastSet | Format-List SamAccountName,Enabled,PasswordLastSet
