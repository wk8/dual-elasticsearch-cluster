#!/bin/bash

# This script generates the VCL for the dual ES cluster.
# 
# It expects the following environment variables to be set:
# - PRIMARY_CLUSTER: a string for comma or space separated <hostname>:<port>
#   strings, listing the ES servers in the main cluster (port are optional and
#   default to 9200)
# - SECONDARY_CLUSTER: same, for the failover cluster
# If they're not set, the user will be prompted
# 
# Additionnally, the following environment variables are optional:
# - VARNISH_CONFIG_DIR: where to put the VCL files - defaults to /etc/varnish
# - MAIN_VCL_FILENAME: the name of the main VCL file - defaults to default.vcl
# - TEMP_DIR: a dir where the current user can create temp files - defaults to
#   /tmp/
#
# Please note it must be run as a user who was write access to
# the $VARNISH_CONFIG_DIR directory
#
# This script might look convoluted at times, but that's largely because I
# wanted it to require only bash built-ins and sed

# this function expects a single hosts string as argument, and sets
# $genVCL_HOSTS, $genVCL_PORTS and $genVCL_BACKENDS arrays accordingly
declare -a genVCL_HOSTS; declare -a genVCL_PORTS; declare -a genVCL_BACKENDS;
genVCL_extract_hosts() {
    local HOST_STRING; local CURRENT_INDEX=0; local S; local I;
    genVCL_HOSTS=(); genVCL_PORTS=(); genVCL_BACKENDS=();
    # according to RFC952 (http://tools.ietf.org/html/rfc952), hostnames can only
    # contain [\.a-zA-Z0-9-], plus we allow : for port separation
    for HOST_STRING in $(sed -E 's/[^\.a-zA-Z0-9:-]+/\n/g' <<< "$@")
    do
        [ -z $HOST_STRING ] && continue
        # separate hostname and port
        I=0
        for S in $(sed "s/:/\n/g" <<< "$HOST_STRING")
        do
            case $I in
                0) genVCL_HOSTS[$CURRENT_INDEX]=$S
                # varnish only allows [0-9a-zA-Z_] in backend names
                # and it also wants the first char to be a letter
                genVCL_BACKENDS[$CURRENT_INDEX]=$(echo "$S" | sed -E 's/^([0-9])/ES_SERVER_\1/g' | sed 's/[^0-9a-zA-Z_]/_/g')
                ;;
                1) genVCL_PORTS[$CURRENT_INDEX]=$S;;
                *) echo "Unexpected hostname string $HOST_STRING" && return 1;;
            esac
            I=$(( $I + 1 ))
        done
        # port defaults to 9200 if none was given
        [[ $I == 1 ]] && genVCL_PORTS[$CURRENT_INDEX]='9200'
        CURRENT_INDEX=$(( $CURRENT_INDEX + 1 ))
    done
    # check we have at least one host
    [[ $CURRENT_INDEX == 0 ]] && echo "No host info found in $@" && return 1
    return 0
}

# first, let's check we have all we need
genVCL_check_or_prompt_hosts() {
    local PROMPT; local PROMPT_NAME=$1; shift 1;
    [ "$@" ] && genVCL_extract_hosts "$@" && genVCL_PROMPTED_HOSTS="$@" && return
    echo "Please enter a list of your $PROMPT_NAME cluster's servers (e.g '1.2.3.4:9300 prod-es-server.local')"
    echo "Note that you can bypass that prompt that by specifying the PRIMARY_CLUSTER and SECONDARY_CLUSTER environment variables"
    echo "(and if you use sudo to make install, don't forget to use the -E flag)"
    read -r PROMPT
    genVCL_check_or_prompt_hosts $PROMPT_NAME $PROMPT
}
[ -z "$PRIMARY_CLUSTER" ] && declare genVCL_PROMPTED_HOSTS && genVCL_check_or_prompt_hosts 'MAIN' && PRIMARY_CLUSTER=$genVCL_PROMPTED_HOSTS
[ -z "$SECONDARY_CLUSTER" ] && declare genVCL_PROMPTED_HOSTS && genVCL_check_or_prompt_hosts 'FAILOVER' && SECONDARY_CLUSTER=$genVCL_PROMPTED_HOSTS

# then let's check we have write access to the config and temp dirs
genVCL_fail() { local EXIT_CODE; [ -z $2 ] && EXIT_CODE=1 || EXIT_CODE=$2; echo $1 && exit $EXIT_CODE; }
[ -z "$VARNISH_CONFIG_DIR" ] && VARNISH_CONFIG_DIR='/etc/varnish'
[ -w "$VARNISH_CONFIG_DIR" ] || genVCL_fail "Current user does NOT have write permissions on $VARNISH_CONFIG_DIR"
[ -z "$TEMP_DIR" ] && TEMP_DIR='/tmp'
[ -w "$TEMP_DIR" ] || genVCL_fail "Current user does NOT have write permissions on $TEMP_DIR"
[ -z "$MAIN_VCL_FILENAME" ] && MAIN_VCL_FILENAME='default.vcl'

# and finally check the needed files are around, and readable
genVCL_CURRENT_DIR=$(dirname $0)
genVCL_check_file() { [ -r "$genVCL_CURRENT_DIR/$1" ] || genVCL_fail "File $genVCL_CURRENT_DIR/$1 is missing or not readable"; }
genVCL_check_file 'es_server.vcl.tpl'
genVCL_check_file 'default.vcl.tpl'
genVCL_check_file 'VCL_dual_cluster_parse_time.c'

# an util function
genVCL_cp_to_cfg_dir() { cp -f $1 "$VARNISH_CONFIG_DIR/$2" || genVCL_fail "Could not update the $VARNISH_CONFIG_DIR/$2 file"; }

# first, let's generate the es_servers.vcl file
# temp file to work on
genVCL_TMP_FILE=$(mktemp "$TEMP_DIR/dual_es.XXXXX")
# this function is just here to factorize code between the 2 clusters
# $1 is the cluster name, $2 the hosts string
genVCL_generate_vcl_servers() {
    local -i I
    local CURRENT_SERVER
    genVCL_extract_hosts "$2" || exit 1
    # first the backends
    for (( I=0; I < ${#genVCL_HOSTS[@]}; I++ ))
    do
        cat "$genVCL_CURRENT_DIR/es_server.vcl.tpl" \
            | sed "s/<BACKEND_NAME>/${genVCL_BACKENDS[I]}/g" \
            | sed "s/<BACKEND_HOST>/${genVCL_HOSTS[I]}/g" \
            | sed "s/<BACKEND_PORT>/${genVCL_PORTS[I]}/g" \
            >> $genVCL_TMP_FILE
    done
    # then the director
    echo "director $1 round-robin {" >> $genVCL_TMP_FILE
    for CURRENT_SERVER in "${genVCL_BACKENDS[@]}"
    do
        echo "    { .backend = $CURRENT_SERVER; }" >> $genVCL_TMP_FILE
    done
    echo "}" >> $genVCL_TMP_FILE
}
genVCL_generate_vcl_servers 'main_cluster' "$PRIMARY_CLUSTER"
genVCL_generate_vcl_servers 'failover_cluster' "$SECONDARY_CLUSTER"
genVCL_cp_to_cfg_dir $genVCL_TMP_FILE 'es_servers.vcl'

# now let's generate the main VCL file - we need to escape slashes in the path
cat "$genVCL_CURRENT_DIR/default.vcl.tpl" \
    | sed "s/<VARNISH_CONFIG_DIR>/$(sed "s/\//\\\\\//g" <<< $VARNISH_CONFIG_DIR)/g" \
    > $genVCL_TMP_FILE
genVCL_cp_to_cfg_dir $genVCL_TMP_FILE "$MAIN_VCL_FILENAME"

# and finally let's make sure the .c file is here
genVCL_cp_to_cfg_dir "$genVCL_CURRENT_DIR/VCL_dual_cluster_parse_time.c" 'VCL_dual_cluster_parse_time.c'

echo "All done! Don't forget to restart Varnish: /etc/init.d/varnish restart"
