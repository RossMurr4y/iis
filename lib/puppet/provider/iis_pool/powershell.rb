require 'puppet/provider/iispowershell'
require 'json'

Puppet::Type.type(:iis_pool).provide(:powershell, :parent => Puppet::Provider::Iispowershell) do
  confine :operatingsystem => :windows
  confine :powershell_version => [:"5.0", :"4.0", :"3.0"]
  
  mk_resource_methods

  # snap_mod global variable decides whether to import the WebAdministration module, or add the WebAdministration snap-in.
  $snap_mod = "$psver = [int]$PSVersionTable.PSVersion.Major; If($psver -lt 4){Add-PSSnapin WebAdministration}else{Import-Module WebAdministration}"

  # In Powershell 3 where we are using the WebAdministration SnapIn, 
  # StartMode doesn't exist and AutoStart is used instead, but is a bool.
  $startMode_autoStart = 
    if :powershell_version == :"3.0"
      'autoStart'
    else
      'startMode'
    end

  def initialize(value = {})
    super(value)
    @property_flush = {
      'poolattrs'    => {},
      'failure'      => {},
      'processModel' => {},
      'recycling'    => {}
    }
  end

  def self.prefetch(resources)
    pools = instances
    resources.keys.each do |pool|
      if provider = pools.find { |s| s.name == pool }
        resources[pool].provider = provider
      end
    end
  end

  def self.poolattrs
    {
      :enable_32bit => 'enable32BitAppOnWin64',
      :state        => 'state',
      :runtime      => 'managedRuntimeVersion',
      :pipeline     => 'managedPipelineMode',
      :startmode    => "#$startMode_autoStart",
      :maxqueue     => 'queueLength'
    }
  end

  def self.failure
    {
      :rapidfailprotection => 'rapidFailProtection'
    }      
  end

  def self.processModel
    {
      :identitytype      => 'identityType',
      :identity          => 'userName',
      :identitypassword  => 'password',
      :idletimeout       => 'idleTimeout',
      :idletimeoutaction => 'idleTimeoutAction',
      :maxprocesses      => 'maxProcesses'
    }
  end

  def self.recycling
    {
      :recyclemins    => 'recycling.periodicRestart.time',
      :recyclesched   => 'recycling.periodicRestart.time.schedule',
      :recyclelogging => 'logEventOnRecycle',
    }
  end

  def self.instances

    inst_cmd = "#$snap_mod; Get-ChildItem 'IIS:\\AppPools\' | ForEach-Object {Get-ItemProperty $_.PSPath | Select Name, state, enable32BitAppOnWin64, queueLength, managedRuntimeVersion, managedPipelineMode, #$startMode_autoStart, processModel, failure, recycling} | ConvertTo-Json -Depth 4 -Compress"
    pool_names = JSON.parse(Puppet::Type::Iis_pool::ProviderPowershell.run(inst_cmd))
    pool_names = [pool_names] if pool_names.is_a?(Hash)
    pool_names.map do |pool|
      pool_hash = {}
      pool_hash[:ensure]                = :present
      pool_hash[:name]                  = pool['name']
      pool_hash[:state]                 = pool['state']
      pool_hash[:enable_32bit]          = pool['enable32BitAppOnWin64']
      pool_hash[:runtime]               = pool['managedRuntimeVersion']
      pool_hash[:pipeline]              = pool['managedPipelineMode']
      pool_hash[:startmode]             = pool["#$startMode_autoStart"]
      pool_hash[:maxqueue]              = pool['queueLength']
      pool_hash[:rapidfailprotection]   = pool['failure']['rapidFailProtection']
      pool_hash[:idletimeout]           = pool['processModel']['idleTimeout']['Minutes']
      pool_hash[:idletimeoutaction]     = pool['processModel']['idleTimeoutAction']
      pool_hash[:maxprocesses]          = pool['processModel']['maxProcesses']
      pool_hash[:identitytype]          = pool['processModel']['identityType']
      pool_hash[:identity]              = pool['processModel']['userName']
      pool_hash[:identitypassword]      = pool['processModel']['password']
      pool_hash[:recyclemins]           = pool['recycling']['periodicRestart']['time']['TotalMinutes']
      pool_hash[:recyclesched]          = pool['recycling']['periodicRestart']['schedule']['collection']
      pool_hash[:recyclelogging]        = pool['recycling']['logEventOnRecycle']
      new(pool_hash)
    end
  end

  def exists?
    @property_hash[:ensure]
  end

  def create
    create_switches = [
      $snap_mod,
      "New-WebAppPool -Name \"#{@resource[:name]}\"",
    ]
    processModel_switches = []
    recycling_switches = []
    failure_switches = []

    # If any of the poolattrs exist in the property_hash, add them to the array of switches
    Puppet::Type::Iis_pool::ProviderPowershell.poolattrs.each do |poolattr, value|
      if @resource[poolattr]
        create_switches << "Set-ItemProperty \"IIS:\\\\AppPools\\#{@resource[:name]}\" \"#{value}\" \"#{@resource[poolattr]}\""
      end
    end

    # Add all the new/updated processModel attrs to the processModel_switches array, and add a single switch for all of them to the create_switches array.
    if @resource[:identitytype] == :"3" || @resource[:identitytype] == :specificUser
      Puppet::Type::Iis_pool::ProviderPowershell.processModel.each do |processModel, value|
        processModel_switches << "#{value}=\"#{@resource[processModel]}\"" if @resource[processModel]
      end
    end
    processModel_value = processModel_switches.join(';')
    create_switches << "Set-ItemProperty \"IIS:\\\\AppPools\\#{@resource[:name]}\" -Name 'processModel' -Value \"@{#{processModel_value}}\""
    
    # Add all the new/updated recycling attrs to the recycling_switches array, and then add a single switch to the create_switches array to set them all.
    Puppet::Type::Iis_pool::ProviderPowershell.recycling.each do |recycle, value|
      recycling_switches << "#{value}=\"#{@resource[recycle]}\"" if @resource[recycle]
    end
    recycling_value = recycling_switches.join(';')
    create_switches << "Set-ItemProperty \"IIS:\\\\AppPools\\#{@property_hash[:name]}\" -Name recycling -Value @{#{recycling_value}}"

    # Add the single failure switch to the create_switches array, if it exists in the property_hash
    # Setting this up as a loop of the array incase we add further attrs from failure.attributes 
    Puppet::Type::Iis_pool::ProviderPowershell.failure.each do |failure, value|
      failure_switches << "#{value}=\"#{@resource[failure]}\"" if @resource[failure]
    end
    failure_value = failure_switches.join(';')
    create_switches << "Set-ItemProperty \"IIS:\\\\AppPools\\#{@resource[:name]}\" -Name failure.rapidFailProtection -Value @{#{recycling_value}}"
    
    # Put it all together, then execute it.
    inst_cmd = create_switches.join(';')
    resp = Puppet::Type::Iis_pool::ProviderPowershell.run(inst_cmd)

    @resource.original_parameters.each_key do |k|
      @property_hash[k] = @resource[k]
    end
    @property_hash[:ensure] = :present unless @property_hash[:ensure]

    exists? ? (return true) : (return false)
  end

  def destroy
    inst_cmd = "#$snap_mod; Remove-WebAppPool -Name \"#{@resource[:name]}\""
    resp = Puppet::Type::Iis_pool::ProviderPowershell.run(inst_cmd)
    raise(resp) unless resp.empty?

    @property_hash.clear
    exists? ? (return false) : (return true)
  end

  Puppet::Type::Iis_pool::ProviderPowershell.poolattrs.each do |property, poolattr|
    define_method "#{property}=" do |value|
      @property_flush['poolattrs'][property.to_sym] = value
      Puppet.debug "Setting Property Hash #{@property_hash[property.to_sym]} to #{value}"
      @property_hash[property.to_sym] = value
      Puppet.debug "Property hash #{property} is #{@property_hash[property.to_sym]}"
    end
  end

  Puppet::Type::Iis_pool::ProviderPowershell.processModel.each do |property, iisname|
    define_method "#{property}=" do |value|
      @property_flush['processModel'][property.to_sym] = value
      @property_hash[property.to_sym] = value
    end
  end

  Puppet::Type::Iis_pool::ProviderPowershell.recycling.each do |property, iisname|
    define_method "#{property}=" do |value|
      @property_flush['recycling'][property.to_sym] = value
      @property_hash[property.to_sym] = value
    end
  end

  # Only one element in the array, but doing this incase we add more attrs later
  Puppet::Type::Iis_pool::ProviderPowershell.failure.each do |property, iisname|
    define_method "#{property}=" do |value|
      @property_flush['failure'][property.to_sym] = value
      @property_hash[property.to_sym] = value
    end
  end

  def start 
    create unless exists?
    @property_hash[:name] = @resource[:name]
    @property_hash[:state] = :Started
    @property_flush['poolattrs']['state'] = :started
    @property_hash[:ensure] = :present
  end

  def stop 
    create unless exists?
    @property_hash[:name] = @resource[:name]
    @property_hash[:state] = :Stopped
    @property_flush['poolattrs']['state'] = :stopped
    @property_hash[:ensure] = :present
  end

  def flush
    # initialize all the arrays we'll need to make the final flush command string (command_array)
    processModel_switches = []
    recycling_switches = []
    failure_switches = []
    command_array = [ $snap_mod ]

    # Gather all the updated 'poolattrs' and add them to the command_array
    @property_flush['poolattrs'].each do |poolattr, value|
      property_name = Puppet::Type::Iis_pool::ProviderPowershell.poolattrs[poolattr]
      # Skip the state poolattr, we'll do it last.
      next if property_name == 'state'
      command_array << "Set-ItemProperty \"IIS:\\\\AppPools\\#{@property_hash[:name]}\" -Name #{property_name} -Value #{value}"
    end
    
    # Check to see if the IdentityType is changing.
    Puppet.debug "teseting if the processmodel flush works"
    if @property_flush['processModel'].keys.any? { |k| [:identitytype,:identity,:identitypassword].include?(k) }
      Puppet.debug "the key section of processmodel flush works"
      identitytype_value =
        if @property_flush.key?(:identitytype)
          @property_flush['processModel'][:identitytype]
        else
          @property_hash[:identitytype]
        end

      # We either set for a SpecificUser (3) with creds, or we set only the identityType. 
      if identitytype_value == (:SpecificUser || :"3")
        username_value =
          if @property_flush.key?(:identity)
            @property_flush['processModel'][:identity]
          else
            @property_hash[:identity]
          end
        password_value =
          if @property_flush.key?(:identitypassword)
            @property_flush['processModel'][:identitypassword]
          else
            @property_hash[:identitypassword]
          end
        command_array << "\$pool = get-item IIS:\\AppPools\\#{@property_hash[:name]}; \$pool.processModel.username = \"#{username_value}\";\$pool.processModel.password = \"#{password_value}\";\$pool.processModel.identityType = \"#{identitytype_value}\"; \$pool | set-item"
      else
        command_array << "\$pool = get-item IIS:\\AppPools\\#{@property_hash[:name]}; \$pool.processModel.identityType = \"#{identitytype_value}\"; \$pool | set-item"
      end      
    end

    #Update the IdleTimeout, IdleTimeoutAction and the maxProcesses if they exist.
    command_array << "\$ts = New-Timespan -Minutes #{@property_flush['processModel'][:idletimeout]}; Set-ItemProperty \"IIS:\\\\AppPools\\#{@property_hash[:name]}\" -name processModel -value @{idletimeout=\$ts}" if @property_flush['processModel'][:idletimeout]
    command_array << "Set-ItemProperty \"IIS:\\\\AppPools\\#{@property_hash[:name]}\" -name processModel -value @{idletimeoutaction=\"#{@property_flush['processModel'][:idletimeoutaction]}\"}" if @property_flush['processModel'][:idletimeoutaction]
    command_array << "Set-ItemProperty \"IIS:\\\\AppPools\\#{@property_hash[:name]}\" -name processModel -value @{maxprocesses=#{@property_flush['processModel'][:maxprocesses]}}" if @property_flush['processModel'][:maxprocesses]

    # Set all the recycling properties    
    command_array << "\$ts = New-Timespan -Minutes #{@property_flush['recycling'][:recyclemins]}; Set-ItemProperty \"IIS:\\\\AppPools\\#{@property_hash[:name]}\" -Name recycling.periodicRestart.time -value \$ts;" if @property_flush['recycling'][:recyclemins]
    command_array << "[string[]]\$RestartTimes = @(#{@property_flush['recycling'][:recyclesched]}); Clear-ItemProperty \"IIS:\\\\AppPools\\#{@property_hash[:name]}\" -Name recycling.periodicRestart.schedule; foreach (\$restartTime in \$RestartTimes){ New-ItemProperty -Path \"IIS:\\\\AppPools\\#{@property_hash[:name]}\" -Name recycling.periodicRestart.schedule -Value @{value=\$restartTime};}" if @property_flush['recycling'][:recyclesched]
    command_array << "Set-ItemProperty \"IIS:\\\\AppPools\\#{@property_hash[:name]}\" -name recycling -value @{logEventOnRecycle=\"#{@property_flush['recycling'][:recyclelogging]}\"}" if @property_flush['recycling'][:recyclelogging]


    
    # Gather all the updated 'failure' values, compile them into an array (failure_switches), and then set them simultaneously.
    # Note: there is currently only one failure property. This is included incase we want to control more failure properties later.
    @property_flush['failure'].each do |property, value|
      failure_switches << "#{property}=\"#{value}\""
    end
    failure_value = failure_switches.join(';')
    command_array << "Set-ItemProperty \"IIS:\\\\AppPools\\#{@property_hash[:name]}\" -Name 'failure' -Value @{#{failure_value}}" unless failure_value.empty? || failure_value.nil?

    # Queue the change of state if necessary.
    if @property_flush['poolattrs']['state']
      state_cmd = "Start-WebAppPool -Name \"#{@property_hash[:name]}\"" if @property_flush['poolattrs']['state'] == :started
      state_cmd = "Stop-WebAppPool -Name \"#{@property_hash[:name]}\"" if @property_flush['poolattrs']['state'] == :stopped
      command_array << state_cmd
    end

    # Join the entire flush command string together, then run it.
    inst_cmd = command_array.join('; ')
    begin
      Puppet.debug "inst_cmd is: #{inst_cmd}"
      Puppet::Type::Iis_pool::ProviderPowershell.run(inst_cmd)
    rescue Puppet::ExecutionFailure => e
      raise(e)
    end
  end

end