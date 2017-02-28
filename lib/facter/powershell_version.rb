require 'facter/util/registrypowershell'

# This is a custom fact for Puppet to gather the installed version of Powershell direct from the registry.
# This will allow us to 'confine' Providers based on the version installed, and create new Providers for
# different Powershell versions.

Facter.add(:powershell_version) do
  confine :kernel => :windows
  setcode do
    powershell_version_string = Facter::Util::Registrypowershell.powershell_version_string_from_registry
  end
end