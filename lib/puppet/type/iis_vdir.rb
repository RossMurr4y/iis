Puppet::Type.newtype(:iis_vdir) do
  desc 'A Virtual Directory of a Website.'
  ensurable

  ### parameters
  newparam(:name, namevar: true) do
    desc 'This is the name of the virtual directory'
    validate do |value|
      raise("#{value} is not a valid virtual directory name") unless value =~ %r{^[a-zA-Z0-9\-\_\/\s]+$}
    end
  end
  
  ### properties
  newproperty(:parent_site) do
    desc 'The site in which this virtual directory resides.'
    validate do |value|
      raise("#{value} is not a valid site name") unless value =~ %r{^[a-zA-Z0-9\-\_\/\s]+$}
    end
  end

  newproperty(:path) do
    desc 'Path to the Virtual Directory folder.'
    validate do |value|
      raise("File paths must be fully qualified, not '#{value}'") unless value =~ %r{^.:(\/|\\)} || value =~ %r{^\/\/[^\/]+\/[^\/]+}
    end
  end

  autorequire(:iis_site) do
    self[:parent_site] if @parameters.include? :parent_site
  end

end