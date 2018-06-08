# Simple_apache
#
# mostly_ drop-in replacement for puppetlabs-apache (where noted) with built-in support for downloading full vhost
# and module configs from git. vhost definitions can be edited in-place for AccessLog, ErrorLog, DocumentRoot or just
# served raw.
#
# `simple_apache` is somewhat a misnomer its simple if your an expert apache admin. Also (and more importantly) the
# module is not called `apache` which would instantly clash with the `puppetlabs` module of the same name.
# @see https://forge.puppet.com/puppetlabs/vcsrepo for details of how to connect to your git repositories of config files
#
# You can adjust base of the paths by setting class parameters. `AccessLog` `ErrorLog` and `DocumentRoot` can be
# adjusted on per-host basis
#
# @example Configuration directory structure
#   /etc/httpd/
#   ├── conf
#   │   ├── httpd.conf                                              <-- main httpd config
#   │   └── magic
#   ├── conf.d                                                      <-- unmanaged config files
#   │   ├── autoindex.conf
#   │   ├── php.conf
#   │   ├── README
#   │   ├── userdir.conf
#   │   └── welcome.conf
#   ├── conf.modules.d                                              <-- module configuration files to load
#   │   ├── 00-base.conf
#   │   ├── 00-systemd.conf
#   │   └── php.conf -> /etc/httpd/modules_available.d/php.conf     <-- symlink to file from git
#   ├── ...
#   ├── modules_available.d                                         <-- all known module configs (from git)
#   │   └── php.conf
#   ├── ...
#   ├── vhosts_available.d                                          <-- all known vhost configs (from git)
#   │   ├── beta.megacorp.com.conf
#   │   ├── dev.megacorp.com.conf
#   │   └── test.megacorp.com.conf
#   └── vhosts_enabled.d                                            <-- edited copies or symlinks of files from git
#     ├── beta.megacorp.com.conf -> /etc/httpd/vhosts_available.d/beta.megacorp.com.conf
#     └── test.megacorp.com.conf
#
# @example DocumentRoot directory structure
#   /var/www/
#   ├── cgi-bin
#   ├── html
#   └── vhosts
#     └── test.megacorp.com                                         <-- one directory per vhost based on ServerName
#       └── index.html
#
# @example Log directory structure
#   /var/log/httpd/
#   ├── access_log                                                  <-- log files from main server process
#   ├── error_log
#   ├── test.megacorp.com-access_log                                <-- separate error/access log for each vhost
#   └── test.megacorp.com-error_log
#
# @example Hiera data for overall server settings
#   simple_apache::server_settings:
#     ServerAdmin: "root@megacorp.com" # pass array here if more then one setting needed
#
# @example Hiera data to install a vhost and edit it for correct directories (defaults)
#   simple_apache::vhosts_enabled:
#     "test.megacorp.com":
#
# @example Hiera data to install a vhost as-is (symlink/no-edits)
#   simple_apache::vhosts_enabled:
#     "test.megacorp.com":
#       raw: true
#
# @example Hiera data to install a vhost with (non-default settings)
#   simple_apache::vhosts_enabled:
#     "test.megacorp.com":
#       docroot: 
#         path: /home/bob/test
#       error_log: /home/bob/test/error.log
#       access_log: /home/bob/test/access.log
#       log_format: '"%h %l %u %t \"%r\" %>s %b \"%{Referer}i\" \"%{User-agent}i\"" combined'
#
# @example Hiera data to install a vhost with specific docroot permissions
#   simple_apache::vhosts_enabled:
#     "test.megacorp.com":
#       docroot: 
#         path: /home/bob/test
#         mode: '2750'
#         owner: deployuser
#         group: apache
#
# @example Hiera data to install a module (file must exist in config files from git)
#   simple_apache::modules_enabled:
#     - "php.conf"
#
# @example Hiera data to configure your git sources
#   simple_apache::vcs_config:
#     "vhosts":
#       source: "https://git.megacorp.com/git/apache-vhosts.git"
#     "modules":
#       source: "https://git.megacorp.com/git/apache-modules.git"
#
# @param apache_name Name of the package to install (puppetlabs-apache compatible)
# @param service_name Name of the service to manage (puppetlabs-apache compatible)
# @param conf_dir Path to main configuration file directory (puppetlabs-apache compatible)
# @param confd_dir Path to configuration fragments (puppetlabs-apache compatible)
# @param mod_dir Path to configuration fragments for modules (puppetlabs-apache compatible)
# @param logroot Path to directory to store all logs in (puppetlabs-apache compatible)
# @param vhost_dir Path to store virtual host docroots under (puppetlabs-apache compatible)
# @param vhost_available_dir Path to checkout virtual host definitions from VCS
# @param vhost_enabled_dir Directory containing active vhost entries
# @param mod_available_dir Path to checkout module configs from VCS
# @param vcs_config Checkout details for config files from git (see examples)
# @param vhosts_enabled Hash of sites to enable (must be present in `vhost_available_dir`)
# @param modules_enabled Array of modules to enable (must be present in `mod_available_dir`)
# @param manage_package `true` to enable management of the package (puppetlabs-apache compatible)
# @param manage_service `true` to enable management of the service (puppetlabs-apache compatible)
# @param apache_user User who should own apache-writable files (puppetlabs-apache compatible)
# @param apache_group Group who should own apache-writable files (puppetlabs-apache compatible)
# @param server_settings Hash of server settings to apply to `httpd.conf` using augeas
class simple_apache(
  String $apache_name,
  String $service_name,
  String $conf_dir,
  String $confd_dir,
  String $mod_dir,
  String $vhost_dir,
  String $logroot,
  String $vhost_available_dir,
  String $mod_available_dir,
  String $vhost_enabled_dir,
  String $apache_user,
  String $apache_group,
  Hash $vcs_config = {},
  Hash[String, Optional[Hash]] $vhosts_enabled = {},
  Array[String] $modules_enabled = [],
  Boolean $manage_package = true,
  Boolean $manage_service = true,
  Hash[String,Variant[String,Array[String]]] $server_settings = {},
) {

  File {
    owner => "root",
    group => "root",
    mode  => "0644",
  }

  Vcsrepo {
    ensure   => latest,
    provider => git,
    notify   => Service[$service_name],
  }


  if $manage_package {
    $package_ref = Package[$apache_name]
    package { $apache_name:
      ensure => present,
    }
  } else {
    $package_ref = undef
  }

  if $manage_service {
    $service_ref = Service[$service_name]
    service { $service_name:
      ensure  => running,
      enable  => true,
      require => $package_ref,
    }
  } else {
    $service_ref = undef
  }

  $main_config_file = "${conf_dir}/httpd.conf"
  fm_prepend { $main_config_file:
    ensure  => present,
    data    => "# Puppet has modified this file from the original!",
    notify  => $service_ref,
    require => $package_ref,
  }

  file { $vhost_dir:
    ensure => directory,
  }

  file { $vhost_enabled_dir:
    ensure => directory,
    notify => $service_ref,
  }

  file { $logroot:
    ensure => directory,
    owner  => $apache_user,
    group  => $apache_group,
    notify => $service_ref,
  }


  file_line { "${main_config_file} IncludeOptional vhosts_enabled/*.conf":
    ensure  => present,
    path    => $main_config_file,
    line    => "IncludeOptional ${vhost_enabled_dir}/*.conf",
    notify  => $service_ref,
    require => $package_ref,
  }

  $server_settings.each |$key, $value| {
    apache_directive { "${key} in ${main_config_file}":
      args    => $value,
      notify  => $service_ref,
      require => $package_ref,
    }
  }


  if has_key($vcs_config, "vhosts") {
    vcsrepo { $vhost_available_dir:
      * => $vcs_config["vhosts"],
    }

  }

  if has_key($vcs_config, "modules") {
    vcsrepo { $mod_available_dir:
      * => $vcs_config["modules"],
    }
  }


  # Activate virtual hosts requested by either symlinking or copying file + editing (from checked out code)
  $vhosts_enabled.each |$key,$opts| {
    $conf_file = "${vhost_enabled_dir}/${key}.conf"
    $conf_file_upstream = "${vhost_available_dir}/${key}.conf"


    $error_log = pick(dig($opts, 'error_log'), "${logroot}/${key}-error_log")
    $error_logroot = dirname($error_log)
    $access_log = pick(dig($opts, 'access_log'), "${logroot}/${key}-access_log")
    $access_logroot = dirname($access_log)
    $docroot = pick(dig($opts, 'docroot', 'path'), "${vhost_dir}/${key}")
    $docroot_owner = pick(dig($opts, 'docroot', 'owner'), 'root')
    $docroot_group = pick(dig($opts, 'docroot', 'group'), 'root')
    $docroot_mode = pick(dig($opts, 'docroot', 'mode'), '0755')


    if ! defined(File[$error_logroot]) {
      file { $error_logroot:
        ensure => directory,
        owner  => $apache_user,
        group  => $apache_group,
        mode   => "0640",
        notify => $service_ref,
      }
    }

    if ! defined(File[$access_logroot]) {
      file { $access_logroot:
        ensure => directory,
        owner  => $apache_user,
        group  => $apache_group,
        mode   => "0640",
        notify => $service_ref,
      }
    }


    file { $docroot:
      ensure => directory,
      owner  => $docroot_owner,
      group  => $docroot_group,
      mode   => $docroot_mode,
      notify => $service_ref,
    }


    if pick(dig($opts, 'raw'), false) {
      # in raw mode we create a simple symlink without any rewriting - you must make sure all dirs match
      # the ones specified in $opts yourself
      file { $conf_file:
        ensure => link,
        target => $conf_file_upstream,
        notify => $service_ref,
      }
    } else {
      $exec_title = "install file ${conf_file}"

      # create a blank file if it is missing (or symlink from 'raw') to fix permissions and trigger the exec
      file { $conf_file:
        ensure => file,
      }

      exec { $exec_title:
        refreshonly => true,
        command     => "/bin/cp ${conf_file_upstream} ${conf_file}",
        subscribe   => [Vcsrepo[$vhost_available_dir], File[$conf_file]],
      }

      Apache_directive {
        ensure  => present,
        notify  => $service_ref,
        require => [Exec[$exec_title], $package_ref],
        context => "VirtualHost",
      }

      apache_directive { "ErrorLog in ${conf_file}":
        args    => $error_log,
      }

      apache_directive { "CustomLog in ${conf_file}":
        args    => [$access_log, pick(dig($opts, 'log_format'), 'combined')]
      }

      apache_directive { "DocumentRoot in ${conf_file}":
        args    => $docroot,
      }

      fm_prepend { $conf_file:
        ensure => present,
        data   => "# Puppet has modified this file from the original!",
        notify => $service_ref,
      }

    }

    # Activate module config files requested by symlinking from checked out code
    $modules_enabled.each |$module| {
      file { "${mod_dir}/${module}":
        ensure => link,
        target => "${mod_available_dir}/${module}",
        notify => $service_ref,
      }
    }
  }
}
