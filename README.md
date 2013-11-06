Dual Elasticsearch Cluster
==========================

This project allows you to have two separate ElasticSearch clusters in sync, 
using Varnish (https://www.varnish-cache.org/).

It is being used in production, but YMMV.


Why would you want this?
------------------------

Your main app servers are in the cloud, in data center A, where the
RAM-intensive servers you need to run your ElasticSearch cluster
are really expensive.

So you turn to a bare metal provider, in data center B, but now you have
your ElasticSearch cluster and your main app servers in two different data
centers: what if there happens to be a network problem and you can't talk to B
any more from A?

Well then, you could also run an ElasticSearch cluster with nodes in both data
centers. Big and powerful bare metal servers, and a few smaller and weaker
nodes in the cloud. So now if there's a connectivity problem between the two
data centers, at least you can still offer some degraded service.

But the problem is now different: when you make a search query to ElasticSearch,
the part of your data that's sharded into the smaller nodes is unlikely to come
up fast enough to appear in your search results. All your results are skewed.

I propose another solution: you run two separate clusters. Your main one, with
cheap and powerful bare metal servers, and your secondary one in the cloud,
with smaller nodes but in the same data center as your main app servers.
Then you add a Varnish server on top of your clusters, and talk to that server
instead of addressing ElasticSearch directly.
Whenever that server receives a GET request, it will try to get the result from
your main cluster, and failing that, will ask your secondary cluster.
If it receives a non-GET request, it will try to play it on your main cluster,
then, if successful, will play it on your secondary cluster.

That way, your two clusters are in sync (the worst that can happen is having
your main cluster slightly ahead), your main cluster handles all the searches
when all is fine, and you can still offer some degraded service when you've
lost the connectivity to your main cluster.

Last but not least, to avoid creating a SPOF in your infrastructure, you might
want to run two Varnish servers instead of just one.


Requirements
------------

- gcc
- GNU make
- GUN sed

(Other versions of sed and make most likely work, but haven't been tested.)


Instructions
-------------

1) The vanilla version of Varnish won't work here: you'll need to install my
   slightly modified version: https://github.com/wk8/Varnish-Cache
   (see installation instructions there)

2) You'll also need xcir's excellent Varnish mod parsereq, available at
   https://github.com/xcir/libvmod-parsereq. Don't forget you need to build it
   against my version of Varnish's sources (see further instructions in xcir's
   README)

3) Then checkout the present repo, and run the tests: make test

4) Finally run make install with root privileges. It will prompt you for the
   hostnames and ports for both your main and secondary clusters, generate the
   appropriate VCL files, and restart Vanish.
   Note that you can skip the prompting by setting shell environment variables
   `PRIMARY_CLUSTER` and `SECONDARY_CLUSTER`. See the comments at the beginning
   of `generate_vcl.sh` for other potentially useful environment variables.

5) Now you can start using both clusters as one! Just point all your
   ElasticSearch clients to your Varnish server instead.


Contributing & feedback
-----------------------

As always, I appreciate bug reports, suggestions, pull requests, feedback...
Feel free to reach me at <wk8.github@gmail.com>
