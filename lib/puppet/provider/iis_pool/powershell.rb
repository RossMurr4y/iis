require 'puppet/provider/iispowershell'
require 'json'

Puppet::Type.type(:iis_pool).provide(:powershell, :parent => Puppet::Provider::Iispowershell) do
  confine :operatingsystem => :windows
  confine :powershell_version => [:"5.0", :"4.0", :"3.0"]
  mk_resource_methods
  
  $snap_mod = case Facter.value(:os)['release']['major']
    when '2008' then 'Add-PSSnapin WebAdministration'
    else 'Import-Module WebAdministration'
  end

  # startMode property is 'autoStart' in PowerShell3
  $startMode_autoStart = case Facter.value(:powershell_version)
    when '3.0' then 'autoStart'
    else 'startMode'
  end

  def initialize(value = {})
    super(value)
    @property_flush = {}
  end

  def self.poolattributes
    {
      :enable_32bit        => 'enable32BitAppOnWin64',
      :state               => 'state',
      :runtime             => 'managedRuntimeVersion',
      :pipeline            => 'managedPipelineMode',
      :startmode           => $startMode_autoStart,
      :maxqueue            => 'queueLength',
      :rapidfailprotection => 'failure.rapidFailProtection',
      :identitytype        => 'processModel.identityType',
      :identity            => 'processModel.userName',
      :identitypassword    => 'processModel.password',
      :idletimeout         => 'processModel.idleTimeout.Minutes',
      :idletimeoutaction   => 'processModel.idleTimeoutAction',
      :maxprocesses        => 'processModel.maxProcesses',
      :recyclemins         => 'recycling.periodicRestart.time.TotalMinutes',
      :recyclesched        => 'recycling.periodicRestart.schedule.collection',
      :recyclelogging      => 'recycling.logEventOnRecycle',
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

  def self.instances
    inst_cmd = "#{$snap_mod}; Get-ChildItem 'IIS:\\AppPools\' | ForEach-Object {Get-ItemProperty $_.PSPath | Select Name, state, enable32BitAppOnWin64, queueLength, managedRuntimeVersion, managedPipelineMode, #{$startMode_autoStart}, processModel, failure, recycling} | ConvertTo-Json -Depth 4 -Compress"
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
      pool_hash[:startmode]             = pool[$startMode_autoStart]
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

    Puppet::Type::Iis_pool::ProviderPowershell.poolattributes.each do |attr, value|
      if @resource[attr]
        Puppet.debug "Setting Attribute: \$pool.#{value} to value: \"#{@resource[attr]}\""
        create_switches << "\$pool.#{value} = \"#{@resource[attr]}\""
      end
    end
    create_switches << "\$pool | Set-Item"
    inst_cmd = create_switches.join(';')

    begin
      Puppet.debug "Create method inst_cmd is: #{inst_cmd}"
      Puppet::Type::Iis_pool::ProviderPowershell.run(inst_cmd)
    rescue Puppet::ExecutionFailure => e
      raise(e)
    end

    @resource.original_parameters.each_key do |k|
      @property_hash[k] = @resource[k]
    end
    
    @property_hash[:ensure] = :present unless @property_hash[:ensure]
    exists? ? (return true) : (return false)
  end

  def destroy
    begin
      uninst_cmd = "#{$snap_mod}; Remove-WebAppPool -Name \"#{@resource[:name]}\""
      Puppet::Type::Iis_pool::ProviderPowershell.run(uninst_cmd)
      @property_hash.clear
    rescue Puppet::ExecutionFailure => e
      raise(e)
    end

    exists? ? (return false) : (return true)

  end

  Puppet::Type::Iis_pool::ProviderPowershell.poolattributes.each do |type_param, ps_prop|
    define_method "#{type_param}=" do |value|
      @property_flush[type_param] = value
      #@property_hash[type_param] = value
    end
  end

  def start 
    create unless exists?
    @property_flush[:state] = :Started
    #@property_hash[:state] = :Started
  end

  def stop 
    create unless exists?
    @property_flush[:state] = :Stopped
    #@property_hash[:state] = :Stopped
  end

  def flush
    command_array = [
      $snap_mod,
      "\$pool = Get-Item \"IIS:\\AppPools\\#{@resource[:name]}\""
    ]

    @property_flush.each do |type_param, value|
      next if type_param == :state
      attribute = Puppet::Type::Iis_pool::ProviderPowershell.poolattributes[type_param]
      Puppet.debug "Flush type_param: #{attribute} being set to: \"#{@property_flush[type_param]}\"" if @property_flush[type_param]
      command_array << "\$pool.#{attribute} = \"#{@property_flush[type_param]}\"" if @property_flush[type_param]
    end

    command_array << "\$ts = New-Timespan -Minutes #{@property_flush[:idletimeout]}; Set-ItemProperty \"IIS:\\AppPools\\#{@property_hash[:name]}\" -name processModel -value @{idletimeout=\$ts}" if @property_flush[:idletimeout]
    command_array << "\$ts = New-Timespan -Minutes #{@property_flush[:recyclemins]}; \$pool.recycling.recyclemins = \$ts" if @property_flush[:recyclemins]
    command_array << "[string[]]\$RestartTimes = @(#{@property_flush[:recyclesched]}); Clear-ItemProperty \"IIS:\\AppPools\\#{@property_hash[:name]}\" -Name recycling.periodicRestart.schedule; foreach (\$restartTime in \$RestartTimes){ New-ItemProperty -Path \"IIS:\\AppPools\\#{@property_hash[:name]}\" -Name recycling.periodicRestart.schedule -Value @{value=\$restartTime};}" if @property_flush[:recyclesched]
    command_array << "\$pool | Set-Item"

    # Change of State.
    command_array << "Start-WebAppPool -Name \"#{@resource[:name]}\"" if @property_flush[:state] == :Started
    command_array << "Stop-WebAppPool -Name \"#{@resource[:name]}\"" if @property_flush[:state] == :Stopped
    
    begin
      flush_cmd = command_array.join('; ')
      Puppet.debug "Puppet Flush is as follows: #{flush_cmd}"
      Puppet::Type::Iis_pool::ProviderPowershell.run(flush_cmd)
    rescue Puppet::ExecutionFailure => e
      raise(e)
    end
  end

end