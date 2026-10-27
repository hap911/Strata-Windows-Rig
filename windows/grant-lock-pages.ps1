# Grants "Lock pages in memory" (SeLockMemoryPrivilege) to the current user via the LSA API.
# Run elevated (the .bat wrapper does that). Takes effect at the NEXT sign-in (no reboot needed - sign out/in is enough).
param([string]$User = "$env:USERDOMAIN\$env:USERNAME")

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Lsa {
    [StructLayout(LayoutKind.Sequential)] public struct LSA_UNICODE_STRING { public ushort Length, MaximumLength; public IntPtr Buffer; }
    [StructLayout(LayoutKind.Sequential)] public struct LSA_OBJECT_ATTRIBUTES { public int Length; public IntPtr RootDirectory, ObjectName; public uint Attributes; public IntPtr SecurityDescriptor, SecurityQualityOfService; }
    [DllImport("advapi32.dll")] public static extern uint LsaOpenPolicy(ref LSA_UNICODE_STRING SystemName, ref LSA_OBJECT_ATTRIBUTES ObjectAttributes, uint DesiredAccess, out IntPtr PolicyHandle);
    [DllImport("advapi32.dll")] public static extern uint LsaAddAccountRights(IntPtr PolicyHandle, IntPtr AccountSid, LSA_UNICODE_STRING[] UserRights, uint CountOfRights);
    [DllImport("advapi32.dll")] public static extern int LsaNtStatusToWinError(uint status);
    [DllImport("advapi32.dll")] public static extern uint LsaClose(IntPtr PolicyHandle);
    [DllImport("advapi32.dll", CharSet = CharSet.Unicode)] public static extern bool ConvertStringSidToSid(string StringSid, out IntPtr Sid);
}
"@

$sid = (New-Object System.Security.Principal.NTAccount($User)).Translate([System.Security.Principal.SecurityIdentifier]).Value
$sidPtr = [IntPtr]::Zero
[void][Lsa]::ConvertStringSidToSid($sid, [ref]$sidPtr)

$objAttr = New-Object Lsa+LSA_OBJECT_ATTRIBUTES
$sysName = New-Object Lsa+LSA_UNICODE_STRING
$policy = [IntPtr]::Zero
$POLICY_CREATE_ACCOUNT = 0x10; $POLICY_LOOKUP_NAMES = 0x800
$st = [Lsa]::LsaOpenPolicy([ref]$sysName, [ref]$objAttr, $POLICY_CREATE_ACCOUNT -bor $POLICY_LOOKUP_NAMES, [ref]$policy)
if ($st -ne 0) { Write-Error ("LsaOpenPolicy failed: " + [Lsa]::LsaNtStatusToWinError($st)); exit 1 }

$right = "SeLockMemoryPrivilege"
$us = New-Object Lsa+LSA_UNICODE_STRING
$us.Length = [uint16]($right.Length * 2)
$us.MaximumLength = [uint16](($right.Length + 1) * 2)
$us.Buffer = [Runtime.InteropServices.Marshal]::StringToHGlobalUni($right)
$st = [Lsa]::LsaAddAccountRights($policy, $sidPtr, @($us), 1)
[void][Lsa]::LsaClose($policy)
if ($st -ne 0) { Write-Error ("LsaAddAccountRights failed: " + [Lsa]::LsaNtStatusToWinError($st)); exit 1 }
Write-Host "Granted SeLockMemoryPrivilege to $User ($sid). Sign out and back in for it to take effect."
