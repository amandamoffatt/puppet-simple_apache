@test "service running" {
    systemctl status httpd
}

@test "test.megacorp.com available" {
    curl http://test.megacorp.com
}