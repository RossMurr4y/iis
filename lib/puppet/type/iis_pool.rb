Puppet::Type.newtype(:iis_pool) do
  desc 'An IIS Application Pool resource type.'
  ensurable

  ### parameters
  newparam(:name, :namevar => true) do
    desc 'The Name of the Application Pool. The Namevar.'
    validate do |value|
      fail("#{name} is not a valid ApplicationPool name.") unless value =~ %r{^[a-zA-Z0-9\-\_\.'\s]+$}
    end
  end

  ### properties
  newproperty(:state) do
    desc 'The State to enforce upon the Application Pool.'
    newvalue(:Stopped) do
      provider.stop
    end
    newvalue(:Started) do
      provider.start
    end
    defaultto :Started
  end

  newproperty(:enable_32bit) do
    desc 'A Boolean to determine if 32bit mode should enabled. Defaults to false.'
    newvalues(false, true)
    aliasvalue(:False, false)
    aliasvalue(:false, false)
    aliasvalue('False', false)
    aliasvalue('false', false)
    aliasvalue(:true, true)
    aliasvalue(:True, true)
    aliasvalue('True', true)
    aliasvalue('true', true)
  end

  newproperty(:runtime) do
    desc 'The version of the .Net Runtime to use for the Application Pool.'
    newvalues(:"v4.0", :"v2.0", :nil)
  end

  newproperty(:pipeline) do
    desc 'The Pipeline mode to use. Values are 0 (Integrated) or 1 (Classic).'
    newvalues(:Integrated, :integrated, :Classic, :classic)
    munge do |value|
      value.capitalize
    end
    aliasvalue(:"0", :Integrated)
    aliasvalue(:"1", :Classic)
  end

  newproperty(:identity) do
    desc 'The Identity value that should control the Application Pool.'
    validate do |value|
      # Regex needs to match account@domain + domain\account formats
      fail("#{value} is not a valid User Identity for an Application Pool") unless value =~ %r{^[a-zA-Z0-9\\\-\_\@\.\s]+$}
    end
  end

  newproperty(:identitypassword) do
    desc 'The password to the Application Pool identity.'
    validate do |value|
      # Needs to validate both ENC[] password hashes and plaintext strings. Likely stored as hiera lookups.
      #fail("#{value} is not a valid Identity Password") unless value =~ ()
    end
  end

  newproperty(:startmode) do
    # In Powershell 3, WebAdministration snapin, the 'startmode' is known as 'AutoStart' and is a bool.
    # We'll accept values for both snap-in and module here, and put the logic in the Provider.
    desc 'How the AppPool should be started.'
    newvalues(:OnDemand, :AlwaysRunning, :true, :false)
    #defaultto :OnDemand
  end

  newproperty(:rapidfailprotection) do
    desc ''
    newvalues(:true, :false)
    #defaultto :true
  end

  newproperty(:identitytype) do
    desc 'The type of Identity to run this AppPool under.'
    newvalues(:LocalSystem, :LocalService, :NetworkService, :SpecificUser, :ApplicationPoolIdentity)
    aliasvalue(:"0", :LocalSystem)
    aliasvalue(:"1", :LocalService)
    aliasvalue(:"2", :NetworkService)
    aliasvalue(:"3", :SpecificUser)
    aliasvalue(:"4", :ApplicationPoolIdentity)
    #defaultto :applicationPoolIdentity
  end

  newproperty(:idletimeout) do
    desc 'The Idle Timeout of the AppPool (in minutes).'
    validate do |value|
      fail("#{value} is not a valid Idle Timeout figgure, in minutes.") unless value =~ %r{^\d+$}
    end
    #defaultto :"20"
  end

  newproperty(:idletimeoutaction) do
    desc 'Action to perform upon AppPool Idle Timeout'
    newvalues(:Suspend, :Terminate)
    #defaultto :"Terminate"
  end

  newproperty(:maxprocesses) do
    desc 'The maximum number of processes to run the AppPool for.'
    validate do |value|
      fail("#{value} is not a valid integer for Max Processes.") unless value =~ %r{^\d+$}
    end
    #defaultto :"1"
  end

  newproperty(:maxqueue) do
    #desc ''
    validate do |value|
      fail("#{value} is not a valid queue length. Must be an Integer.") unless value =~ %r{^\d+$}
    end
    #defaultto :"1000"
  end

  newproperty(:recyclemins) do
    desc 'How frequently (if at all) the AppPool recycles.'
    validate do |value|
      fail("#{value} is not a valid Recycle time. Must be an Integer.") unless value =~ %r{^\d+$}
    end
  end

  newproperty(:recyclesched) do
    #desc ''
    validate do |value|
      fail("#{value} is not a valid Recycle schedule. Must be in format: hh:mm:ss.") unless value =~ %r{^\d{2}:\d{2}:\d{2}$|^\b\d{2}:\d{2}:\d{2}(?:,\b\d{2}:\d{2}:\d{2}\b)*$}
    end
  end

  newproperty(:recyclelogging) do
    desc 'Logging type to record on AppPool recycle.'
    newvalues(:time, :requests, :schedule, :memory, :isApiUnhealthy, :onDemand, :configChange, :privateMemory)
  end

end