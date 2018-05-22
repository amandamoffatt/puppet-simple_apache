#@PDQTest
class { "simple_apache":
  vcs_config => {
    "vhosts" => {
      source => "https://github.com/GeoffWilliams/puppet-simple_apache-integration",
    }
  },
  vhosts_enabled => {
    "test.megacorp.com" => {
    }
  }
}
