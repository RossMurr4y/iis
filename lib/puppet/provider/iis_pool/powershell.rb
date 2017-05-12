require 'puppet/provider/iispowershell'
require 'json'

Puppet::Type.type(:iis_pool).provide(:powershell, :parent => Puppet::Provider::Iispowershell) do
  confine :operatingsystem => :windows
  confine :powershell_version => [:"5.0", :"4.0", :"3.0"]
  
  mk_resource_methods

  # snap_mod: import the WebAdministration module, or add the WebAdministration snap-in.
  if Facter.value(:os)['release']['major'] != '2008'
    $snap_mod = 'Import-Module WebAdministration'
  else
    $snap_mod = 'Add-PSSnapin WebAdministration'
  end

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
      :startmode    => "startMode_autoStart",
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

    inst_cmd = "#{$snap_mod}; Get-ChildItem 'IIS:\\AppPools\' | ForEach-Object {Get-ItemProperty $_.PSPath | Select Name, state, enable32BitAppOnWin64, queueLength, managedRuntimeVersion, managedPipelineMode, startMode_autoStart, processModel, failure, recycling} | ConvertTo-Json -Depth 4 -Compress"
    pools_listed = Puppet::Type::Iis_pool::ProviderPowershell.run(inst_cmd)
    pool_json = if pools_listed == ''
                 [] # https://github.com/RossMurr4y/iis/issues/7
               else
                 JSON.parse(pools_listed)
               end
    pool_json = [pool_json] if pool_json.is_a?(Hash)
    pool_json.map do |pool|
      pool_hash = {}
      pool_hash[:ensure]                = :present
      pool_hash[:name]                  = pool['name']
      pool_hash[:state]                 = pool['state']
      pool_hash[:enable_32bit]          = pool['enable32BitAppOnWin64']
      pool_hash[:runtime]               = pool['managedRuntimeVersion']
      pool_hash[:pipeline]              = pool['managedPipelineMode']
      pool_hash[:startmode]             = pool['startMode_autoStart']
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
      "\$pool = Get-Item \"IIS:\\\\AppPools\\#{@resource[:name]}\""
    ]

    # If any of the poolattrs exist in the property_hash, add them to the array of switches
    Puppet::Type::Iis_pool::ProviderPowershell.poolattrs.each do |poolattr, value|
      if @resource[poolattr]
        Puppet.debug "Attempting \$pool.poolattrs.#{value} = \"#{@resource[poolattr]}\""
        create_switches << "\$pool.poolattrs.#{value} = \"#{@resource[poolattr]}\""
      end
    end
    
    create_switches << "\$pool | Set-Item"
    inst_cmd = create_switches.join(';')
    Puppet.debug "Creating App Pool with the following command:"
    Puppet.debug "#{inst_cmd}"
    resp = Puppet::Type::Iis_pool::ProviderPowershell.run(inst_cmd)

    @resource.original_parameters.each_key do |k|
      @property_hash[k] = @resource[k]
    end
    @property_hash[:ensure] = :present unless @property_hash[:ensure]

    exists? ? (return true) : (return false)
  end

  def destroy
    inst_cmd = "#{$snap_mod}; Remove-WebAppPool -Name \"#{@resource[:name]}\""
    resp = Puppet::Type::Iis_pool::ProviderPowershell.run(inst_cmd)
    raise(resp) unless resp.empty?

    @property_hash.clear
    exists? ? (return false) : (return true)
  end

  Puppet::Type::Iis_pool::ProviderPowershell.poolattrs.each do |property, poolattr|
    define_method "#{property}=" do |value|
      @property_flush['poolattrs'][property.to_sym] = value
      @property_hash[property.to_sym] = value
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
    command_array = []

    # <pool>
    command_array << "#{$snap_mod}; \$pool = Get-Item \"IIS:\\\\AppPools\\#{@property_hash[:name]}\"" if @property_flush

    # poolAttrs
    @property_flush['poolattrs'].each do |key, value|
      property_name = Puppet::Type::Iis_pool::ProviderPowershell.poolattrs[poolattr]
      # Skip the state poolattr, we'll do it last.
      next if property_name == 'state'
      command_array << "\$pool.poolattrs.#{value} = \"#{@property_flush['poolattrs'][key]}\"" if @property_flush['poolattrs'][key]
      Puppet.debug "Flushing poolattrs.#{value} and setting as \"#{@property_flush['poolattrs'][key]}\" "
    end

    # processModel
    @property_flush['processModel'].each do |key, value|
      next if key == :idletimeout
      command_array << "\$pool.processModel.#{value} = \"#{@property_flush['processModel'][key]}\"" if @property_flush['processModel'][key]
    end
    command_array << "\$ts = New-Timespan -Minutes #{@property_flush['processModel'][:idletimeout]}; Set-ItemProperty \"IIS:\\\\AppPools\\#{@property_hash[:name]}\" -name processModel -value @{idletimeout=\$ts}" if @property_flush['processModel'][:idletimeout]

    # recycling
    command_array << "\$ts = New-Timespan -Minutes #{@property_flush['recycling'][:recyclemins]}; \$pool.recycling.recyclemins = \$ts" if @property_flush['recycling'][:recyclemins]
    command_array << "[string[]]\$RestartTimes = @(#{@property_flush['recycling'][:recyclesched]}); Clear-ItemProperty \"IIS:\\\\AppPools\\#{@property_hash[:name]}\" -Name recycling.periodicRestart.schedule; foreach (\$restartTime in \$RestartTimes){ New-ItemProperty -Path \"IIS:\\\\AppPools\\#{@property_hash[:name]}\" -Name recycling.periodicRestart.schedule -Value @{value=\$restartTime};}" if @property_flush['recycling'][:recyclesched]
    command_array << "\$pool.recycling.logEventOnRecycle = \"#{@property_flush['recycling'][:recyclelogging]}\"" if @property_flush['recycling'][:recyclelogging]
    
    # failure
    command_array << "\$pool.failure.rapidfailprotection = \"#{@property_flush['failure'][:rapidfailprotection]}\"" if @property_flush['failure'][:rapidfailprotection]

    # </pool>
    command_array << "\$pool | Set-Item"

    # Change of State.
    if @property_flush['poolattrs']['state'] == :Started
      command_array << "Start-WebAppPool -Name \"#{@property_hash[:name]}\""
    else
      command_array << "Stop-WebAppPool -Name \"#{@property_hash[:name]}\""
    end
    
    # Join the entire flush command string together, then run it.
    inst_cmd = command_array.join('; ')
    begin
      Puppet.debug "Puppet Flush is as follows:"
      Puppet.debug "#{inst_cmd}"
      Puppet::Type::Iis_pool::ProviderPowershell.run(inst_cmd)
    rescue Puppet::ExecutionFailure => e
      raise(e)
    end
  end

end