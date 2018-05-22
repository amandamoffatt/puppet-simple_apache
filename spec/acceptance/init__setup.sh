#!/bin/bash
# If this file exists it will be run on the system under test before puppet runs
# to setup any prequisite test conditions, etc
echo "127.0.0.1 test.megacorp.com\n" >> /etc/hosts