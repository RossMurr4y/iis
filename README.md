# iis

#### Table of Contents

1. [Description](https://github.com/RossMurr4y/puppet-iis#description)
1. [Setup - The basics of getting started with iis](https://github.com/RossMurr4y/puppet-iis#setup)
1. [Resource Types - Types, Attributes and valid values](https://github.com/RossMurr4y/puppet-iis#resource-types)
      * [iis_site](https://github.com/RossMurr4y/puppet-iis#iis_site)
      * [iis_pool](https://github.com/RossMurr4y/puppet-iis#iis_pool)
      * [iis_app](https://github.com/RossMurr4y/puppet-iis#iis_app)
      * [iis_vdir](https://github.com/RossMurr4y/puppet-iis#iis_vdir)
1. [Limitations - OS compatibility, etc.](https://github.com/RossMurr4y/puppet-iis#limitations)

## Description

This Puppet Module is intended to allow Puppet to manage IIS resources - *Site's*, *Application Pools*, *Applications* and *Virtual Directories* - on older OS's
(Starting from **Windows Server 2008**) as well as more current OS (Windows Server 2012).

This module will work with older Windows Server 2008 servers, **[upgraded to at least WMF 3.0](https://www.microsoft.com/en-au/download/details.aspx?id=34595)** and with the **[WebAdministration PowerShell SnapIn](https://www.iis.net/learn/manage/powershell/installing-the-iis-powershell-snap-in)** installed. Later OS's using this Module will instead utilise the WebAdministration Powershell Module which will already be available. Both have 
very similar functionalities, and this module will account for any deviations. 

## Setup

At the current time, this module assumes the following:
* IIS itself is already installed and configgured (future feature)
* Servers using WMF3.0 have the [**WebAdministration**](https://www.iis.net/downloads/microsoft/powershell) 
  SnapIn installed (future feature)

## Resource Types

The following Resource Types are available:

* [iis_site](https://github.com/RossMurr4y/puppet-iis#iis_site) : [properties](https://github.com/RossMurr4y/puppet-iis#attribute-values-for-iis_site)
* [iis_pool](https://github.com/RossMurr4y/puppet-iis#iis_pool) : [properties](https://github.com/RossMurr4y/puppet-iis#attribute-values-for-iis_pool)
* [iis_app](https://github.com/RossMurr4y/puppet-iis#iis_app) : [properties](https://github.com/RossMurr4y/puppet-iis#attribute-values-for-iis_app)
* [iis_vdir](https://github.com/RossMurr4y/puppet-iis#iis_vdir) : [properties](https://github.com/RossMurr4y/puppet-iis#attribute-values-for-iis_vdir)

## Type Attributes

### **iis_site**

Example manifest entry for the creation of an IIS Website called 'TestWebsite'

```puppet
iis_site { 'TestWebsite':
  ensure     => 'present',
  path       => 'D:\inetpub\content\TestWebsite',
  app_pool   => 'TestApplicationPool',
  state      => 'Started',
  hostheader => 'testwebsiteheader',
  protocol   => 'http',
  ip         => '127.0.0.1',
  port       => '80',
  ssl        => 'false',
}
```

#### Attribute Values for iis_site

|Property        | Description|
|----------------|------------|
**path:**       | must be an absolute filepath.
**state:**      | stopped, started. Defaults to started.
**app_pool:**   | Must match against the following regex (Defaults to 'DefaultAppPool'): %r{[a-zA-Z0-9\-\_\'\s]+$}
**hostheader:** | Must match against the following regex OR 'false': %r{[a-zA-Z0-9\-\_\'\.\s]+$} 
**protocol:**   | http, https. Defaults to http.
**ip:**         | either *, or a valid IPv4 or IPv6 address. Defaults to *.
**port:**       | Must be a valid port number. Integer, not string.
**ssl:**        | true, false. Defaults to false.

### iis_pool

Example manifest entry for the creation of an Application Pool called 'TestPool'

```puppet
iis_pool { 'TestPool':
  ensure              => 'present',
  state               => 'Started',
  enable_32bit        => 'false',
  runtime             => 'v4.0',
  pipeline            => 'Integrated',
  identitytype        => 'SpecificUser',
  identity            => '<DOMAIN>\TestUserAccount',
  identitypassword    => 'hopefullynotplaintextpwd',
  startmode           => 'OnDemand',
  rapidfailprotection => 'true',
  idletimeout         => '8000',
  idletimeoutaction   => 'Terminate',
  maxprocesses        => 1,
  maxqueue            => 1,
  recyclemins         => 60,
  recyclesched        => "23:30:00",
}
```

#### Attribute Values for iis_pool

|Property   | Description|
|-----------|-------------|
**state:**               | Stopped, Started. Defaults to Started.
**enable_32bit:**        | true, false.
**runtime:**             | v4.0, v2.0, nil.
**pipeline:**            | Integrated, Classic, 0 (Integrated), 1 (Classic)
**identitytype:**        | LocalSystem (or 0), LocalService (or 1), 
                         |  NetworkService (or 2), 
                         |  SpecificUser (or 3), 
                         |  ApplicationPoolIdentity (or 4)
**identity:**            | Must match regex: %r{^[a-zA-Z0-9\\\-\_\@\.\s]+$} Can Start with a DOMAIN.
**identitypassword:**    | No validation. Please don't just use plaintext. Use hiera and/or EYAML.
**startmode:**           | OnDemand, AlwaysRunning, true, false.
**rapidfailprotection:** | true, false.
**idletimeout:**         | Integer. 
**idletimeoutaction:**   | Suspend, Terminate.
**maxprocesses:**        | Integer.
**maxqueue:**            | Integer.
**recyclemins:**         | Integer.
**recyclesched:**        | String in the format of "HH:MM:SS"

### iis_app

Example manifest entry for the creation of an IIS Application called 'MyTestApp'.

```puppet
iis_app { 'D:\inetpub\content\MyTestSite\MyTestApp':
  ensure       => 'present',
  name         => 'MyTestApp',
  app_pool     => 'MyTestAppPool',
  parent_site  => 'MyTestSite',
}
```

#### Attribute Values for iis_app

|Property      | Description|
|--------------|------------|
**physicalpath:** | Must be an absolute filepath. This is also the namevar, so title your resource accordingly (see example above). This is to prevent duplicate resource names on a server hosting many Web Apps.
**app_pool:**     | Must match against regex: %r{[a-zA-Z0-9\-\_'\s]+$}. Defaults to DefaultAppPool.
**parent_site:**  | Must match against regex: %r{^[a-zA-Z0-9\/\-\_\.'\s]+$}.

### iis_vdir

Example manifest entry for the creation of a Virtual Directory.

```puppet
iis_vdir { '/MyTestVDir':
  parent_site => 'MyTestSite',
  path => 'C:\VdirContents\MyTestVDir',
}
```

#### Attribute Values for iis_vdir

|Property     | Description|
|-------------|------------|
parent_site: | Must match against regex: %r{^[a-zA-Z0-9\-\_\/\s]+$}
path:        | Must be a fully qualified filepath.

## Limitations

Compatible with  the following:

### Operating Systems
* Windows Server 2008 (with installed WebAdministration Powershell SnapIn and WMF 3.0+)
* Windows Server 2012R2

Other Operating Systems may very well be compatible, however have not as yet been tested against.

### Puppet

Testing has been performed with the following version(s) of Puppet:

* 2016.5.1

### Ruby

Testing has been performed with the following version(s) of Ruby:

* 2.1.9

