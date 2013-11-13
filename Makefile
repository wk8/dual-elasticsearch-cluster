.PHONY: install build test

.SILENT: install build test

SHELL=/bin/bash

ROOT_DIR := $(realpath $(dir $(lastword $(MAKEFILE_LIST))))

all: build

build:
	echo "Building the VCL files to $(ROOT_DIR)/build"
	BUILD_DIR=$(ROOT_DIR)/build $(ROOT_DIR)/generate_vcl.sh

install:
	echo "Generating the VCL files..."
	$(ROOT_DIR)/generate_vcl.sh
	echo "Restarting Varnish..."
	/etc/init.d/varnish restart

# just one test for now
# FIXME: have tests on the install script and the VCL
test:
	gcc -D DC_PARSE_TIME_UNIT_TESTS_MAIN VCL_dual_cluster_parse_time.c -o test.x
	./test.x
	rm test.x

clean:
	git clean -Xf
