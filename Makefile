.PHONY: install test

.SILENT: install test

ROOT_DIR := $(realpath $(dir $(lastword $(MAKEFILE_LIST))))

all: install

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
