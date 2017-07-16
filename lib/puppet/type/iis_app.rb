require 'pathname'

Puppet::Type.newtype(:iis_app) do
  desc 'An IIS Virtual Application.'
  ensurable

  def self.title_patterns
    [[/(.*)/m, [[:name]]]]
  end

  ### parameters
  newparam(:physicalpath, namevar: true) do
    desc 'The fully-qualified filepath to the IIS Application root directory'
    validate do |value|
      unless Pathname.new(value).absolute?
        raise("Invalid path value of #{value}")
      end
    end
  end

  newparam(:name) do
    desc 'The Name of the Application within the Website.'
    validate do |value|
      raise("#{value} is not a valid Application name") unless value =~ %r{^[a-zA-Z0-9\/\-\_\.'\s]+$}
    end
  end

  ### properties

  newproperty(:app_pool) do
    desc 'The Application Pool used by the Application.'
    validate do |value|
      raise("#{value} is not a valid Application Pool name") unless value =~ /[a-zA-Z0-9\-\_'\s]+$/
    end
    defaultto :DefaultAppPool
  end

  newproperty(:parent_site) do
    desc 'The Site that this Application belongs under.'
    validate do |value|
      raise("#{value} is not a valid website name") unless value =~ %r{^[a-zA-Z0-9\/\-\_\.'\s]+$}
    end
  end

  autorequire(:iis_site) do
    self[:parent_site] if @parameters.include? :parent_site
  end

  autorequire(:iis_pool) do
    self[:app_pool] if @parameters.include? :app_pool
  end
end
