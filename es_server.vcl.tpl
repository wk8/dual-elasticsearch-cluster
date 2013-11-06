backend <BACKEND_NAME> {
    .host = "<BACKEND_HOST>";
    .port = "<BACKEND_PORT>";
    .probe = {
        .request =
            "GET / HTTP/1.1"
            "Host: 127.0.0.1"
            "Connection: close";
        .interval = 5s;
        .timeout = 1s;
        .window = 5;
        .threshold = 2;
    }
    .connect_timeout = 0.5s;
    .first_byte_timeout = 0.5s;
    .between_bytes_timeout = 0.5s;
}
