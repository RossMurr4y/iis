module Facter::Util::Registrypowershell
  def self.powershell_version_string_from_registry
    require 'win32/registry'
    Win32::Registry::HKEY_LOCAL_MACHINE.open('SOFTWARE\Microsoft\PowerShell\3\PowerShellEngine')['PowerShellVersion']
  rescue Win32::Registry::Error => e
    Facter.debug "Accessing SOFTWARE\\Microsoft\\PowerShell\\3\\PowerShellEngine gave an error: #{e}"
    Facter.debug 'Powershell is probably v1'
    nil
  end
end
