# Simple_apache
#
# _mostly_ drop-in replacement for puppetlabs-apache with built-in
# support for downloading full vhost and module configs from git
#
# @param apache_name Name of the package to install
# @param service_name Name of the service to manage
# @param conf_dir Path to main configuration file directory
# @param confd_dir Path to configuration fragments
# @param mod_dir Path to configuration fragments for modules
# @param vhost_dir Path to store virtual host docroots under
# @param vhost_available_dir Path to checkout virtual host definitions from VCS to
# @param vcs_config Checkout details for config files from git (see examples)
# @param vhosts_enabled Hash of sites to enable (must be present in `vhost_available_dir`)
# @param manage_package `true` to enable management of the package
# @param manage_service `true` to enable management of the service
class simple_apache(
  String $apache_name,
  String $service_name,
  String $conf_dir,
  String $confd_dir,
  String $mod_dir,
  String $vhost_dir,
  String $vhost_log_dir,
  String $vhost_available_dir,
  String $vhost_enabled_dir,
  String $apache_user,
  String $apache_group,
  Hash $vcs_config = {},
  Hash[String, Hash] $vhosts_enabled = {},
  Boolean $manage_package = true,
  Boolean $manage_service = true,
  Hash[String,Variant[String,Array[String]]] $server_settings = {},
) {

  File {
    owner => "root",
    group => "root",
    mode  => "0644",
  }

  $main_config_file = "${conf_dir}/httpd.conf"
  fm_prepend { $main_config_file:
    ensure => present,
    data   => "# Puppet has modified this file from the original!",
    notify => Service[$service_name],
  }

  if $manage_package {
    package { $apache_name:
      ensure => present,
    }
  }

  if $manage_service {
    service { $service_name:
      ensure => running,
      enable => true,
    }
  }

  file { $vhost_dir:
    ensure => directory,
  }

  file { $vhost_enabled_dir:
    ensure => directory,
    notify => Service[$service_name],
  }

  file { $vhost_log_dir:
    ensure => directory,
    owner  => $apache_user,
    group  => $apache_group,
    notify => Service[$service_name],
  }


  file_line { "${main_config_file} IncludeOptional vhosts_enabled/*.conf":
    ensure => present,
    path   => $main_config_file,
    line   => "IncludeOptional ${vhost_enabled_dir}/*.conf",
    notify => Service[$service_name],
  }

  $server_settings.each |$key, $value| {
    apache_directive { "${key} in ${main_config_file}":
      args => $value,
    }
  }

  vcsrepo {
    default:
      ensure   => latest,
      provider => git,
      notify   => Service[$service_name],
    ;

    $vhost_available_dir:
      * => $vcs_config["vhosts"],
  }

  $vhosts_enabled.each |$key,$opts| {
    $conf_file = "${vhost_enabled_dir}/${key}.conf"
    $conf_file_upstream = "${vhost_available_dir}/${key}.conf"


    $error_log = pick($opts['error_log'], "${vhost_log_dir}/${key}-error_log")
    $error_log_dir = dirname($error_log)
    $access_log = pick($opts['access_log'], "${vhost_log_dir}/${key}-access_log")
    $access_log_dir = dirname($access_log)
    $docroot = pick($opts['docroot'], "${vhost_dir}/${key}")

    if ! defined(File[$error_log_dir]) {
      file { $error_log_dir:
        ensure => directory,
        owner  => $apache_user,
        group  => $apache_group,
        mode   => 0640,
        notify => Service[$service_name],
      }
    }

    if ! defined(File[$access_log_dir]) {
      file { $access_log_dir:
        ensure => directory,
        owner  => $apache_user,
        group  => $apache_group,
        mode   => 0640,
        notify => Service[$service_name],
      }
    }


    file { $docroot:
      ensure => directory,
      notify => Service[$service_name],
    }


    if pick($opts['raw'], false) {
      # in raw mode we create a simple symlink without any rewriting - you must make sure all dirs match
      # the ones specified in $opts yourself
      file { $conf_file:
        ensure => link,
        target => $conf_file_upstream,
        notify => Service[$service_name],
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
        notify => Service[$service_name],
        require => Exec[$exec_title],
        context => "VirtualHost",
      }

      apache_directive { "ErrorLog in ${conf_file}":
        args    => $error_log,
      }

      apache_directive { "CustomLog in ${conf_file}":
        args    => [$access_log, pick($opts['log_format'], 'combined')]
      }

      apache_directive { "DocumentRoot in ${conf_file}":
        args    => $docroot,
      }

      fm_prepend { $conf_file:
        ensure => present,
        data   => "# Puppet has modified this file from the original!",
        notify => Service[$service_name],
      }

    }


  }
}