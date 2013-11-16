include "<VARNISH_CONFIG_DIR>/es_servers.vcl";

import parsereq;

C{
#include "<VARNISH_CONFIG_DIR>/VCL_dual_cluster_parse_time.c"
}C

sub vcl_recv {
    // first, extract the timeout param, if any
    parsereq.init();
    set req.http.X-dual-cluster-timeout = parsereq.param(get, "timeout");
    if (req.request == "GET") {
        // try the main cluster, failover to the secondary if necessary
        set req.backend = main_cluster;
        set req.http.X-dual-cluster-origin = "main";
        if (!req.backend.healthy) {
            set req.backend = failover_cluster;
            // mark it as being served by the failover cluster
            set req.http.X-dual-cluster-origin = "failover";
        }
        return (pass);
    }
    // not a 'GET' request, we need to play it on both clusters
    if (req.http.X-dual-cluster-next == "secondary") {
        // already been played on the main
        set req.backend = failover_cluster;
    } else {
        // let's play it on the main
        set req.backend = main_cluster;
    }
    return (pass);
}

sub vcl_pass {
    // set the proper bereq timeout
C{
    VCL_set_bereq_timeout(sp);
}C
    return (pass);
}

sub vcl_fetch {
    // if the request's been played _successfully_ on the main cluster, let's play it on the other one
    if (req.request != "GET" && req.http.X-dual-cluster-next != "secondary" && beresp.status >= 200 && beresp.status < 300) {
        set req.http.X-dual-cluster-next = "secondary";
        return (restart);
    }
    return (deliver);
}

sub vcl_deliver {
    // let the client know who served the GET request
    if (req.request == "GET") {
        set resp.http.X-dual-cluster-origin = req.http.X-dual-cluster-origin;
    }
    set resp.http.Connection = "close";
    return (deliver);
}
