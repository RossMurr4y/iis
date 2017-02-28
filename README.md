# iis

#### Table of Contents

1. [Description](#description)
1. [Setup - The basics of getting started with iis](#setup)
1. [Resource Types - Types, Attributes and valid values](#Resource Types)
      * [iis_site](#Type Attributes-iis_site)
      * [iis_pool](#Type Attributes-iis_pool)
      * [iis_app](#Type Attributes-iis_app)
      * [iis_vdir](#Type Attributes-iis_vdir)
1. [Reference - An under-the-hood peek at what the module is doing and how](#reference)
1. [Limitations - OS compatibility, etc.](#limitations)
1. [Development - Guide for contributing to the module](#development)

## Description

This Puppet Module is intended to allow Puppet to manage IIS resources (Site's, 
Application Pools, Applications and Virtual Directories) on older OS's
(Windows Server 2008) as well as more current OS (Windows Server 2012). 

This module will work with older Windows Server 2008 servers, upgraded to at least
WMF 3.0 which is the lowest supported version for 'ConvertTo-Json'. Later OS's using 
this Module will instead utilise the WebAdministration Powershell Module. Both have 
very similar functionalities, and the module will account for any deviations. 

## Setup

At the current time, this module assumes the following:
* IIS itself is already installed and configgured (future feature)
* Servers using WMF3.0 have the [WebAdministration](https://www.iis.net/downloads/microsoft/powershell) 
  SnapIn installed (future feature)

## Resource Types

The following Resource Types are available:

* [iis_site](#Type Attributes-iis_site)
    * [attributes](Type Attributes-iis_site-Attribute Values for iis_site)
* [iis_pool](#Type Attributes-iis_pool)
    * [attributes](Type Attributes-iis_pool-Attribute Values for iis_pool)
* [iis_app](#Type Attributes-iis_app)
    * [attributes](Type Attributes-iis_app-Attribute Values for iis_app)
* [iis_vdir](#Type Attributes-iis_vdir)
    * [attributes](Type Attributes-iis_vdir-Attribute Values for iis_vdir)

## Type Attributes

### iis_site

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

The following values are valid for their corresponding attributes:

path:       must be an absolute filepath.

state:      stopped, started. Defaults to started.

app_pool:   Must match against the following regex: %r{[a-zA-Z0-9\-\_\'\s]+$}
            Defaults to 'DefaultAppPool'

hostheader: Must match against the following regex: %r{[a-zA-Z0-9\-\_\'\.\s]+$} 
            OR 'false'

protocol:   http, https. Defaults to http.

ip:         either *, or a valid IPv4 or IPv6 address. Defaults to *.

port:       Must be a valid port number. Integer, not string.

ssl:        true, false. Defaults to false.

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

The following values are valid for their corresponding attributes:

state:               Stopped, Started. Defaults to Started.

enable_32bit:        true, false.

runtime:             v4.0, v2.0, nil.

pipeline:            Integrated, Classic, 0 (Integrated), 1 (Classic)

identitytype:        LocalSystem (or 0), LocalService (or 1), 
                     NetworkService (or 2), SpecificUser (or 3), 
                     ApplicationPoolIdentity (or 4)

identity:            Must match regex: %r{^[a-zA-Z0-9\\\-\_\@\.\s]+$} Can Start with a DOMAIN.

identitypassword:    No validation. Please don't just use plaintext. Use hiera and/or EYAML.

startmode:           OnDemand, AlwaysRunning, true, false.

rapidfailprotection: true, false.

idletimeout:         Integer. 

idletimeoutaction:   Suspend, Terminate.

maxprocesses:        Integer.

maxqueue:            Integer.

recyclemins:         Integer.

recyclesched:        String in the format of "HH:MM:SS"

### iis_app

Example manifest entry for the creation of an IIS Application called 'MyTestApp'.

```puppet
iis_app { 'D:\inetpub\content\MyTestSite\MyTestApp':
  ensure       => 'present',
  name         => 'MyTestApp',
  app_pool     => 'MyTestAppPool',
  site         => 'MyTestSite',
}
```

#### Attribute Values for iis_app

The following values are valid for their corresponding attributes:

physicalpath: Must be an absolute filepath. This is also the namevar, so title
              your resource accordingly (see example above). This is to prevent
              duplicate resource names on a server hosting many Web Apps.

app_pool:     Must match against regex: %r{[a-zA-Z0-9\-\_'\s]+$}. Defaults to
              DefaultAppPool.

site:         Must match against regex: %r{^[a-zA-Z0-9\/\-\_\.'\s]+$}.

### iis_vdir

Example manifest entry for the creation of a Virtual Directory.

```puppet
iis_vdir { '/MyTestVDir':
  site => 'MyTestSite',
  path => 'C:\VdirContents\MyTestVDir',
}
```

#### Attribute Values for iis_vdir

The following values are valid for their corresponding attributes:

site: Must match against regex: %r{^[a-zA-Z0-9\-\_\/\s]+$}

path: Must be a fully qualified filepath.

## Limitations

Compatible with  the following:

### Operating Systems
* Windows Server 2008 (with installed WebAdministration Powershell SnapIn and WMF 3.0+)
* Windows Server 2012R2

### Puppet
* 2016.5.1

### Ruby
<TBA>

