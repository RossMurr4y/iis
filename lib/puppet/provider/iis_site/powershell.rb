require 'puppet/provider/iispowershell'
require 'json'

Puppet::Type.type(:iis_site).provide(:powershell, :parent => Puppet::Provider::Iispowershell) do
  confine :operatingsystem => :windows
  confine :powershell_version => [:"5.0", :"4.0", :"3.0"]

  # snap_mod: import the WebAdministration module, or add the WebAdministration snap-in.
  if Facter.value(:os)['release']['major'] != '2008'
    $snap_mod = 'Import-Module WebAdministration'
  else
    $snap_mod = 'Add-PSSnapin WebAdministration'
  end

  mk_resource_methods

  def self.authenticationtypes
    {
      Anonymous: 'system.webServer/security/authentication/anonymousAuthentication',
      ASP:       'system.webServer/security/authentication/aspAuthentication',
      Basic:     'system.webServer/security/authentication/basicAuthentication',
      Digest:    'system.webServer/security/authentication/digestAuthentication',
      Forms:     'system.webServer/security/authentication/formsAuthentication',
      Windows:   'system.webServer/security/authentication/windowsAuthentication'
    }
  end

  def initialize(value = {})
    super(value)
    @property_flush = {
      'itemproperty'   => {},
      'binders'        => {}
    }
  end

  def self.instances
    inst_cmd = <<-POWERSHELL.gsub(/^ {6}/, '')
      #{$snap_mod}; `
      Get-ChildItem \"IIS:\\Sites\" | ForEach-Object { `
        Get-ItemProperty $_.PSPath | Select name, physicalPath, applicationPool, hostHeader, state, bindings `
      } | ConvertTo-JSON -Depth 4 -Compress
    POWERSHELL

    # auth_cmd = <<-POWERSHELL.sub(/\n$/, '')
    #  #{$snap_mod}; `
    #  Get-ChildItem \"IIS:\\Sites\" | ForEach-Object { `
    #  $auth = Get-WebConfigurationProperty -Filter \"System.webServer/security/authentication/*\" -Name 'Enabled' -Location $_.Name `
    #  } | Where-Object {$_.Value -eq 'True'}; `
    #  $result = $auth.ItemXPath.SubString('42'); `
    #  $result -join ','
    # POWERSHELL

    auth_cmd = <<-POWERSHELL.gsub(/^ {6}/, '')
      $types = @(`
        'system.webServer/security/authentication/anonymousAuthentication', `
        'system.webServer/security/authentication/basicAuthentication', `
        'system.webServer/security/authentication/digestAuthentication', `
        'system.webServer/security/authentication/windowsAuthentication'`
      )`
      #{$snap_mod}; `
      Get-ChildItem \"IIS:\\Sites\" | ForEach-Object { `
        $authentications = Get-WebConfiguration -filter $types -Name 'Enabled' `
        -PSPath \"IIS:\\Sites\\$_.Name\" `
      }; $authentications | ForEach {$_.SectionPath}
    POWERSHELL

    begin
      Puppet.debug "inst_cmd running: Currently looks like #{inst_cmd}"
      sites_listed = Puppet::Type::Iis_site::ProviderPowershell.run(inst_cmd)
      Puppet.debug "auth_cmd running. Currently looks like #{auth_cmd}"
      auths_enabled = Puppet::Type::Iis_site::ProviderPowershell.run(auth_cmd)
    rescue Puppet::ExecutionFailure => e
      raise(e)
    end

    site_json = if sites_listed == ''
                  [] # https://github.com/RossMurr4y/iis/issues/7
                else
                  JSON.parse(sites_listed)
                end
    site_json = [site_json] if site_json.is_a?(Hash)
    site_json.map do |site|
      site_hash               = {}
      site_hash[:ensure]      = :present
      site_hash[:state]       = site['state']
      site_hash[:name]        = site['name']
      site_hash[:path]        = site['physicalPath']
      site_hash[:app_pool]    = site['applicationPool']
      binding_collection      = site['bindings']['Collection']
      bindings                = binding_collection.first['bindingInformation']
      site_hash[:protocol]    = site['bindings']['Collection'].first['protocol']
      site_hash[:ip]          = bindings.split(':')[0]
      site_hash[:port]        = bindings.split(':')[1]
      site_hash[:hostheader]  = bindings.split(':')[2]
      site_hash[:ssl]         = if site['bindings']['Collection'].first['sslFlags'].nil? || site['bindings']['Collection'].first['sslFlags'] == 0
                                # The JSON generated by Powershell 3 and 4 appears to differ. 
                                # The SSL flag returns Nil if absent in 3, but 0 if empty in 4.
                                  :false
                                else
                                  :true
                                end
      site_hash[:authtypes] = auths_enabled
      new(site_hash)
    end
  end   

  def self.prefetch(resources)
    sites = instances
    resources.keys.each do |site|
      if provider = sites.find { |s| s.name == site }
        resources[site].provider = provider
      end
    end
  end

  def exists?
    @property_hash[:ensure] == :present
  end

  def create
    create_switches = [
      "-Name \"#{@resource[:name]}\"",
      "-Port #{@resource[:port]}",
      "-IP \"#{@resource[:ip]}\"",
      "-HostHeader \"#{@resource[:hostheader]}\"",
      "-PhysicalPath \"#{@resource[:path]}\"",
      "-ApplicationPool \"#{@resource[:app_pool]}\"",
      '-Force'
    ]

    if @resource[:ssl] == :true
      create_switches.insert(-2, '-Ssl')
    end  

    unless @resource[:state] == :stopped
      create_switches << "; Start-Website -Name \"#{@resource[:name]}\"" 
    end

    inst_cmd = "#{$snap_mod}; New-Website #{create_switches.join(' ')}"
    resp = Puppet::Type::Iis_site::ProviderPowershell.run(inst_cmd)

    @resource.original_parameters.each_key do |k|
      @property_hash[k] = @resource[k]
    end
    @property_hash[:ensure]      = :present
    @property_hash[:port]        = @resource[:port]
    @property_hash[:ip]          = @resource[:ip]
    @property_hash[:hostheader]  = @resource[:hostheader]
    @property_hash[:path]        = @resource[:path]
    @property_hash[:ssl]         = @resource[:ssl]
    @property_hash[:app_pool]    = @resource[:app_pool]
    @property_hash[:state]       = @resource[:state]
    @property_hash[:protocol]    = @resource[:protocol]

    exists? ? (return true) : (return false)
  end

  def destroy
    inst_cmd = "#{$snap_mod}; Remove-Website -Name \"#{@resource[:name]}\""
    resp = Puppet::Type::Iis_site::ProviderPowershell.run(inst_cmd)
    raise(resp) unless resp.empty?
    @property_hash.clear

    exists? ? (return false) : (return true)
  end

  def self.iisnames
    {
      name:     'name',
      path:     'physicalPath',
      app_pool: 'applicationPool',
    }
  end

  Puppet::Type::Iis_site::ProviderPowershell.iisnames.each do |property, iisname|
    next if property == :ensure
    define_method "#{property}=" do |value|
      @property_flush['itemproperty'][iisname.to_sym] = value
      @property_hash[property.to_sym] = value
    end
  end


  def self.binders
    %w(
      protocol
      ip
      port
      hostheader
      ssl
    )
  end

  Puppet::Type::Iis_site::ProviderPowershell.binders.each do |property|
    define_method "#{property}=" do |value|
      @property_flush['binders'][property.to_sym] = value
      @property_hash[property.to_sym] = value
    end
  end

  def state=(value)
    @property_flush['state'] = value
    @property_hash[:state] = value
  end

  def flush
    command_array = [ $snap_mod ]

    # For Each 'itemproperty' that exists in the @property_flush array, queue it.
    @property_flush['itemproperty'].each do |iisname, value|
      command_array << "Set-ItemProperty -Path \"IIS:\\\\Sites\\#{@property_hash[:name]}\" -Name \"#{iisname}\" -Value \"#{value}\""
    end

    # Queue up any changes to the site bindings if necessary.
    # If there are any changes queued in the property_flush['binders'],
    # create a variable for each binder, and use the property_flush (desired state)
    # value if it exists, else use the property_hash value (existing state)
    if @property_flush['binders']
      protocol_flushvar   = @property_flush['binders']['protocol']   ? @property_flush['binders']['protocol']   : @property_hash[:protocol]
      ip_flushvar         = @property_flush['binders']['ip']         ? @property_flush['binders']['ip']         : @property_hash[:ip]
      port_flushvar       = @property_flush['binders']['port']       ? @property_flush['binders']['port']       : @property_hash[:port]
      hostheader_flushvar = @property_flush['binders']['hostheader'] ? @property_flush['binders']['hostheader'] : @property_hash[:hostheader]
      ssl_flushvar        = @property_flush['binders']['ssl']        ? @property_flush['binders']['ssl']        : @property_hash[:ssl]

      bind_cmd = "Set-ItemProperty -Path \"IIS:\\\\Sites\\#{@property_hash[:name]}\" -Name Bindings -Value @{protocol=\"#{protocol_flushvar}\";bindingInformation=\"#{ip_flushvar}:#{port_flushvar}:#{hostheader_flushvar}\""
      bind_cmd << '; sslFlags=0' if @property_flush['binders'][:ssl] && @property_flush['binders'][:ssl] != :false
      bind_cmd << '}'
      command_array << bind_cmd
    end  

    # Queue the change of state if necessary.
    if @property_flush['state']
      state_cmd = "Start-Website -Name \"#{@property_hash[:name]}\"" if @property_flush['state'] == :started
      state_cmd = "Stop-Website -Name \"#{@property_hash[:name]}\"" if @property_flush['state'] == :stopped
      command_array << state_cmd
    end

    # Finally, run all the things queued up.
    inst_cmd = command_array.join('; ')
    Puppet.debug "Running Command from method Flush: #{inst_cmd}"
    begin
      Puppet::Type::Iis_site::ProviderPowershell.run(inst_cmd)
    rescue Puppet::ExecutionFailure => e
      raise(e)
    end
  end

end