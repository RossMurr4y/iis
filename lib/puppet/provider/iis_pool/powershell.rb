require 'puppet/provider/iispowershell'
require 'json'

Puppet::Type.type(:iis_pool).provide(:powershell, :parent => Puppet::Provider::Iispowershell) do
  confine :operatingsystem => :windows
  confine :powershell_version => [:"5.0", :"4.0", :"3.0"]
  mk_resource_methods

  # Account for differences in Win2008
  case Facter.value(:os)['release']['major']
  when '2008'
    $snap_mod = 'Add-PSSnapin WebAdministration' # Use snapin, not module
    $startMode_autoStart = 'autoStart'           # PS object property uses diff name
  else
    $snap_mod = 'Import-Module WebAdministration'
    $startMode_autoStart = 'startMode'
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
      :recyclesched        => 'recycling.periodicRestart.schedule',
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
    inst_cmd = "#{$snap_mod}; Get-ChildItem \"IIS:\\AppPools\" | ForEach-Object {Get-ItemProperty $_.PSPath | Select Name, state, enable32BitAppOnWin64, queueLength, managedRuntimeVersion, managedPipelineMode, #{$startMode_autoStart}, processModel, failure, recycling} | ConvertTo-Json -Depth 4 -Compress"
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


  if Facter.value(:os)['release']['major'] == '2008'
    $identityType_alias =                        
    case @resource[:identitytype]              # IdentityType must end up as the Int
    when 0, :LocalSystem then 0                # value (2008 only), but cant make that 
    when 1, :LocalService then 1               # default as all other OS's convert it
    when 2, :NetworkService then 2             # to String once its in IIS - which 
    when 3, :SpecificUser then 3               # prevents resource idempotency
    when 4, :ApplicationPoolIdentity then 4
    else 
        4
    end
  else
    $identityType_alias = @resource[:identitytype]
  end


  def exists?
    @property_hash[:ensure]
  end

  def create
    command_array = [
      $snap_mod,
      "New-WebAppPool -Name \"#{@resource[:name]}\""
    ]

    Puppet::Type::Iis_pool::ProviderPowershell.poolattributes.each do |type_param, value|
      if @resource[type_param]
        case type_param
          when :startmode
            if value == 'autoStart'
              boolvalue = true if @resource[type_param] == 'OnDemand' || @resource[type_param] == 'true'
              boolvalue = false if @resource[type_param] == 'AlwaysRunning' || @resource[type_param] == 'false'
              Puppet.debug "Create StartMode: known as #{value} and is being set to #{boolvalue}"
              command_array << "Set-ItemProperty \"IIS:\\AppPools\\#{@resource[:name]}\" -Name #{value} -value #{boolvalue}"
            else
              stringvalue = 'OnDemand' if @resource[type_param] == 'true' ||  @resource[type_param] == 'OnDemand'
              stringvalue = 'AlwaysRunning' if @resource[type_param] == 'false'  || @resource[type_param] == 'AlwaysRunning'
              Puppet.debug "Create StartMode is known as #{value} and is being set to #{stringvalue}"
              command_array << "Set-ItemProperty \"IIS:\\AppPools\\#{@resource[:name]}\" -Name #{value} -value #{stringvalue}"
            end
          when :idletimeout, :recyclemins
            Puppet.debug "Create #{type_param}: being set to: \"#{@resource[type_param]}\""
            command_array << "Set-ItemProperty \"IIS:\\AppPools\\#{@resource[:name]}\" -Name #{value} -value ([TimeSpan]::FromMinutes(#{@resource[attribute]}))"
          when :recyclesched
            Puppet.debug "Create type_param: #{type_param} being set to: \"#{@resource[type_param]}\""
            command_array << "Clear-ItemProperty \"IIS:\\AppPools\\#{@resource[:name]}\" -Name #{value}"
            command_array << "[string[]]\$RestartTimes = @(#{@resource[:recyclesched]})"
            command_array << "ForEach ([TimeSpan]\$restartTime in \$RestartTimes){ New-ItemProperty \"IIS:\\AppPools\\#{@resource[:name]}\" -Name #{value} -Value @{value=\$restartTime};}"
          when :identitytype
            Puppet.debug "Create #{type_param}: being set to: \"#{$identityType_alias}\""
            command_array << "Set-ItemProperty \"IIS:\\AppPools\\#{@resource[:name]}\" -Name #{value} -value #{$identityType_alias}"
        else 
          Puppet.debug "Create #{type_param}: being set to: \"#{@resource[type_param]}\""
          command_array << "Set-ItemProperty \"IIS:\\AppPools\\#{@resource[:name]}\" -Name #{value} -value #{@resource[type_param]}"
        end
      end
    end

    inst_cmd = command_array.join(';')

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
      if type_param == :identitytype
        @property_flush[:identitytype] = $identityType_alias
        @property_hash[:identitytype] = $identityType_alias
      else
        @property_flush[type_param] = value
        @property_hash[type_param] = value
      end
    end
  end

  def start 
    create unless exists?
    @property_flush[:state] = :Started
    @property_hash[:state] = :Started
  end

  def stop 
    create unless exists?
    @property_flush[:state] = :Stopped
    @property_hash[:state] = :Stopped
  end

  def flush
    command_array = [ $snap_mod ]

    @property_flush.each do |type_param, value|
      attribute = Puppet::Type::Iis_pool::ProviderPowershell.poolattributes[type_param]
      case type_param
        when :startmode
          if @poolattributes[attribute] == 'autoStart'
            boolvalue = true if @property_flush[type_param] == 'OnDemand' || @property_flush[type_param] == 'true'
            boolvalue = false if @property_flush[type_param] == 'AlwaysRunning' || @property_flush[type_param] == 'false'
            Puppet.debug "Flush StartMode is known as #{attribute} and is being set to #{boolvalue}"
            command_array << "Set-ItemProperty \"IIS:\\AppPools\\#{@resource[:name]}\" -Name #{attribute} -value #{boolvalue}"
          else
            stringvalue = 'OnDemand' if @property_flush[type_param] == 'true' || @property_flush[type_param] == 'OnDemand'
            stringvalue = 'AlwaysRunning' if @property_flush[type_param] == 'false' || @property_flush[type_param] == 'AlwaysRunning'
            Puppet.debug "Flush StartMode is known as #{attribute} and is being set to #{stringvalue}"
            command_array << "Set-ItemProperty \"IIS:\\AppPools\\#{@resource[:name]}\" -Name #{attribute} -value #{stringvalue}"
          end
        when :idletimeout, :recyclemins
          Puppet.debug "Flush #{type_param}: #{attribute} being set to: \"#{@property_flush[type_param]}\""
          command_array << "Set-ItemProperty \"IIS:\\AppPools\\#{@property_hash[:name]}\" -Name #{attribute} -value ([TimeSpan]::FromMinutes(#{@property_flush[type_param]}))"
        when :recyclesched
          Puppet.debug "Flush #{type_param}: #{attribute} being set to: \"#{@property_flush[type_param]}\""
          command_array << "Clear-ItemProperty \"IIS:\\AppPools\\#{@property_hash[:name]}\" -Name #{attribute}"
          command_array << "[string[]]\$RestartTimes = @(#{@property_flush[type_param]})"
          command_array << "ForEach ([Timespan]\$restartTime in \$RestartTimes){ New-ItemProperty \"IIS:\\AppPools\\#{@property_hash[:name]}\" -Name #{attribute} -Value @{value=\$restartTime};}"
        when :state then next
        else 
          Puppet.debug "Flush #{type_param}: #{attribute} being set to: \"#{@property_flush[type_param]}\""
          command_array << "Set-ItemProperty \"IIS:\\AppPools\\#{@property_hash[:name]}\" -Name #{attribute} -value #{@property_flush[type_param]}"
      end
    end

    # start/stop, or clear the array of initializing commands.
    if command_array.length > 1
      command_array << "Start-WebAppPool -Name \"#{@resource[:name]}\"" if @property_flush[:state] == :Started
      command_array << "Stop-WebAppPool -Name \"#{@resource[:name]}\"" if @property_flush[:state] == :Stopped
    else
      command_array.clear
    end
    
    begin
      flush_cmd = command_array.join('; ')
      Puppet.debug "Puppet Flush is as follows: #{flush_cmd}"
      Puppet::Type::Iis_pool::ProviderPowershell.run(flush_cmd)
    rescue Puppet::ExecutionFailure => e
      raise(e)
    end
  end

end