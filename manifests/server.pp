# == Define: openvpn::server
#
# This define creates the openvpn server instance and ssl certificates
#
#
# === Parameters
#
# [*country*]
#   String.  Country to be used for the SSL certificate
#
# [*province*]
#   String.  Province to be used for the SSL certificate
#
# [*city*]
#   String.  City to be used for the SSL certificate
#
# [*organization*]
#   String.  Organization to be used for the SSL certificate
#
# [*email*]
#   String.  Email address to be used for the SSL certificate
#
# [*compression*]
#   String.  Which compression algorithim to use
#   Default: comp-lzo
#   Options: comp-lzo or '' (disable compression)
#
# [*dev*]
#   String.  Device method
#   Default: tun
#   Options: tun (routed connections), tap (bridged connections)
#
# [*user*]
#   String.  Group to drop privileges to after startup
#   Default: nobody
#
# [*group*]
#   String.  User to drop privileges to after startup
#   Default: depends on your $::osfamily
#
# [*ipp*]
#   Boolean.  Persist ifconfig information to a file to retain client IP
#     addresses between sessions
#   Default: false
#
# [*local*]
#   String.  Interface for openvpn to bind to.
#   Default: $::ipaddress_eth0
#   Options: An IP address or '' to bind to all ip addresses
#
# [*logfile*]
#   String.  Logfile for this openvpn server
#   Default: false
#   Options: false (syslog) or log file name
#
# [*port*]
#   Integer.  The port the openvpn server service is running on
#   Default: 1194
#
# [*proto*]
#   String.  What IP protocol is being used.
#   Default: tcp
#   Options: tcp or udp
#
# [*status_log*]
#   String.  Logfile for periodic dumps of the vpn service status
#   Default: "${name}/openvpn-status.log"
#
# [*server*]
#   String.  Network to assign client addresses out of
#   Default: None.  Required in tun mode, not in tap mode
#
# [*push*]
#   Array.  Options to push out to the client.  This can include routes, DNS
#     servers, DNS search domains, and many other options.
#   Default: []
#
#
# === Examples
#
#   openvpn::client {
#     'my_user':
#       server      => 'contractors',
#       remote_host => 'vpn.mycompany.com'
#    }
#
# * Removal:
#     Manual process right now, todo for the future
#
#
# === Authors
#
# * Raffael Schmid <mailto:raffael@yux.ch>
# * John Kinsella <mailto:jlkinsel@gmail.com>
# * Justin Lambert <mailto:jlambert@letsevenup.com>
#
# === License
#
# Copyright 2013 Raffael Schmid, <raffael@yux.ch>
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
define openvpn::server(
  $country,
  $province,
  $city,
  $organization,
  $email,
  $compression = 'comp-lzo',
  $dev = 'tun0',
  $user = 'nobody',
  $cipher = 'BF-CBC',
  $group = false,
  $ipp = false,
  $ip_pool = [],
  $local = $::ipaddress_eth0,
  $logfile = false,
  $port = '1194',
  $proto = 'tcp',
  $mute = '20',
  $verb = '4',
  $keepalive = '10 120',
  $log_append = "${name}/openvpn.log",
  $status_log = "${name}/openvpn-status.log",
  $server = '',
  $push = [],
  $dh_key = 'undef',
  $ca_cert = 'undef',
  $ca_key = 'undef',
  $server_cert = 'undef',
  $server_key = 'undef'
) {

  include openvpn
    Class['openvpn::install'] ->
    Openvpn::Server[$name] ~>
    Class['openvpn::service']

    $tls_server = $proto ? {
      /tcp/   => true,
      default => false
    }

    $group_to_set = $group ? {
      false   => $openvpn::params::group,
      default => $group
    }

    file {
        ["/etc/openvpn/${name}", "/etc/openvpn/${name}/client-configs", "/etc/openvpn/${name}/download-configs" ]:
            ensure  => directory;
    }

    file { "/etc/openvpn/${name}/easy-rsa":
        recurse => true,
        ensure  => directory,
        notify  => Exec["fix_easyrsa_file_permissions_${name}"],
        source  => "puppet:///modules/openvpn/easy-rsa-2.0",
    }

    exec {
        "fix_easyrsa_file_permissions_${name}":
            refreshonly => true,
            command     => "/bin/chmod 755 /etc/openvpn/${name}/easy-rsa/*";
    }

    file {
        "/etc/openvpn/${name}/easy-rsa/vars":
            ensure  => present,
            content => template('openvpn/vars.erb'),
            require => File["/etc/openvpn/${name}/easy-rsa"];
    }

    file {
      "/etc/openvpn/${name}/easy-rsa/openssl.cnf":
        require => File["/etc/openvpn/${name}/easy-rsa"];
    }
    if $openvpn::params::link_openssl_cnf == true {
        File["/etc/openvpn/${name}/easy-rsa/openssl.cnf"] {
            ensure => link,
            target => "/etc/openvpn/${name}/easy-rsa/openssl-1.0.0.cnf"
        }
    }
    if ( $dh_key != 'undef' ) {
        file { "/etc/openvpn/${name}/easy-rsa/keys/dh1024.pem":
            ensure  => present,
            purge   => true,
            recurse => true,
            content => $dh_key,
            require  => File["/etc/openvpn/${name}/easy-rsa/vars"];
        }
    } else {
        exec {
            "generate dh param ${name}":
              command  => '. ./vars && ./clean-all && ./build-dh',
              cwd      => "/etc/openvpn/${name}/easy-rsa",
              creates  => "/etc/openvpn/${name}/easy-rsa/keys/dh1024.pem",
              provider => 'shell',
              require  => File["/etc/openvpn/${name}/easy-rsa/vars"];
        }
    }
    if ( $ca_cert != 'undef' ) {
        file { "/etc/openvpn/${name}/easy-rsa/keys/ca.crt":
            ensure  => present,
            purge   => true,
            recurse => true,
            content => $ca_key,
            require  => File["/etc/openvpn/${name}/easy-rsa/vars"];
        }
    }
    if ( $ca_key != 'undef' ) {
        file { "/etc/openvpn/${name}/easy-rsa/keys/ca.key":
            ensure  => present,
            purge   => true,
            recurse => true,
            content => $ca_key,
            require  => File["/etc/openvpn/${name}/easy-rsa/vars"];
        }
    } else {
        exec {
            "initca ${name}":
            command  => '. ./vars && ./pkitool --initca',
            cwd      => "/etc/openvpn/${name}/easy-rsa",
            creates  => "/etc/openvpn/${name}/easy-rsa/keys/ca.key",
            provider => 'shell',
            require  => [ Exec["generate dh param ${name}"], File["/etc/openvpn/${name}/easy-rsa/openssl.cnf"] ];
        }
    }
    if ( $server_cert != 'undef' ) {
        file { "/etc/openvpn/${name}/easy-rsa/keys/server.crt":
            ensure  => present,
            purge   => true,
            recurse => true,
            content => $server_cert,
            require  => File["/etc/openvpn/${name}/easy-rsa/vars"];
        }
    } 
    if ( $server_key != 'undef' ) {
        file { "/etc/openvpn/${name}/easy-rsa/keys/server.key":
            ensure  => present,
            purge   => true,
            recurse => true,
            content => $server_key,
            require  => File["/etc/openvpn/${name}/easy-rsa/vars"];
        }
    }else {
        exec {
            "generate server cert ${name}":
            command  => '. ./vars && ./pkitool --server server',
            cwd      => "/etc/openvpn/${name}/easy-rsa",
            creates  => "/etc/openvpn/${name}/easy-rsa/keys/server.key",
            provider => 'shell',
            require  => Exec["initca ${name}"];
        }
    }

    file {
        "/etc/openvpn/${name}/keys":
            ensure  => link,
            target  => "/etc/openvpn/${name}/easy-rsa/keys",
            require => File["/etc/openvpn/${name}/easy-rsa"];
    }

    if $::osfamily == 'Debian' {
      concat::fragment {
        "openvpn.default.autostart.${name}":
          content => "AUTOSTART=\"\$AUTOSTART ${name}\"\n",
          target  => '/etc/default/openvpn',
          order   => 10;
      }
    }

    file {
      "/etc/openvpn/${name}.conf":
        owner   => root,
        group   => root,
        mode    => '0444',
        content => template('openvpn/server.erb');
    }
}
