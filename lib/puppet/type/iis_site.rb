require 'pathname'
require 'resolv'
require 'puppet/property/list'

Puppet::Type.newtype(:iis_site) do
  desc 'Creates and manages IIS Websites.'
  ensurable

  # Setting this title_pattern will ensure a resource title sets the :name to the same value.
  # Without this, it will try to assign it to the key-attribute. Both :name and :path (which
  # is the namevar) are key-attributes so Puppet will fall over.
  def self.title_patterns
    [[/(.*)/m, [[:name]]]]
  end

  ### parameters
  newparam(:name, namevar: true) do
    desc 'The displayname for the website.'
    validate do |value|
      raise("#{name} is not a valid website name") unless value =~ %r{^[a-zA-Z0-9\/\-\_\.'\s]+$}
    end
    defaultto :path
  end

  ### properties
  newproperty(:path) do
    desc 'The fully-qualified filepath to the root of the IIS Site. '
    validate do |value|
      raise("Invalid path value of #{value}") unless Pathname.new(value).absolute?
    end
  end

  newproperty(:state) do
    desc 'The state to enforce upon the Site.'
    munge(&:capitalize)
    newvalues(:stopped, :Stopped, :started, :Started)
    defaultto :Started
  end

  newproperty(:app_pool) do
    desc 'The Application Pool that the IIS site should use.'
    validate do |value|
      raise("#{app_pool} is not a valid Application Pool name") unless value =~ /[a-zA-Z0-9\-\_\'\s]+$/
    end
    defaultto :DefaultAppPool
  end

  newproperty(:hostheader) do
    desc 'The Websites host header.'
    validate do |value|
      raise("#{hostheader} is not a valid Host Header for a Site.") unless value =~ /[a-zA-Z0-9\-\_\'\.\s]+$/ || value == :false
    end
  end

  newproperty(:protocol) do
    desc 'The network protocol the site should use. Either HTTP or HTTPS.'
    newvalues(:http, :https)
    defaultto :http
  end

  newproperty(:ip) do
    desc 'The IP Address the site should use. Valid for both IPv4 and IPv6 addresses.'
    validate do |value|
      unless (value =~ Resolv::IPv4::Regex) || (value =~ Resolv::IPv6::Regex) || value == :"*" ? true : false
        raise("Invalid IP value. #{value} is not a valid IPv4/6 Address format.")
      end
    end
    defaultto :"*"
  end

  newproperty(:port) do
    desc 'The port number of the website. Must be an integer.'
    munge(&:to_i)
    defaultto 80
  end

  newproperty(:ssl) do
    desc 'Should SSL be enabled or not. Boolean value.'
    newvalues(:false, :true)
    defaultto :false
  end

  newproperty(:authtypes, array_matching: :all :parent => Puppet::Property::List) do
  desc 'An array of all enabled Authentication Types (Anon, Basic, Digest, Windows). Absent values are disabled.'
  newvalues(:Anonymousauthentication, :Basicauthentication, :Digestauthentication, :Windowsauthentication)
  aliasvalue(:A, :Anonymousauthentication)
  aliasvalue(:B, :Basicauthentication)
  aliasvalue(:D, :Digestauthentication)
  aliasvalue(:W, :Windowsauthentication)
  munge(&:capitalize)
  end

  autorequire(:iis_pool) do
    self[:app_pool] if @parameters.include? :app_pool
  end

end
