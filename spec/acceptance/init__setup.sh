#!/bin/bash
set -x
echo "127.0.0.1 test.megacorp.com" >> /etc/hosts

# install mod_php and remove its shipped config file so we can test our own
yum install -y mod_php
rm /etc/httpd/conf.modules.d/10-php.conf