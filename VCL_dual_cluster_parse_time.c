#include <string.h> /* strlen  */
#include <stdlib.h> /* strtod */
#include <float.h>  /* DBL_MAX */

#define EPSILON 1E-10

// C implementation of the Elasticsearch Java function 'parseTimeValue'
// https://github.com/elasticsearch/elasticsearch/blob/v0.90.5/src/main/java/org/elasticsearch/common/unit/TimeValue.java#L228-L255
// returns the value in seconds, as expected by varnish
static double VCL_parse_time_value(const char* string)
{
    char* end;
    double result;
    size_t suffix_size;

    if (!string) return 0;
    result = strtod(string, &end);
    if (result == 0) return 0;
    suffix_size = string - end + strlen(string);
    if (suffix_size == 0) {
        // they are milliseconds
        result /= 1000;
    } else {
        switch(end[suffix_size - 1]) {
            case 'w': result *= 7;
            case 'd': result *= 24;
            case 'h':
            case 'H': result *= 60;
            case 'm': result *= 60;
            // distinguish between "s" and "ms"
            case 's': if (suffix_size == 1) break;
            case 'S': result /= 1000;
        }
    }
    return result;
}

// main use case: by the VCL
#ifndef DC_PARSE_TIME_UNIT_TESTS_MAIN

void VCL_set_bereq_timeout(struct sess *sp) {
    double bereq_timeout = 2 * VCL_parse_time_value(VRT_GetHdr(sp, HDR_REQ, "\027X-dual-cluster-timeout:"));
    if (bereq_timeout <= EPSILON) {
        // no timeout!
        bereq_timeout = DBL_MAX;
    }
    VRT_l_bereq_first_byte_timeout(sp, bereq_timeout);
}

// the rest is used to unit-test the VCL_parse_time_value function (crappy, OK, but small enough to do that here)
# else

#include <assert.h> /* assert */
#include <math.h>   /* fabs   */
#include <stdio.h>  /* printf */

int main() {
    size_t i;
    const char* inputs[] = {"30s", "10ms", "1.5s", "1.5m", "1.5h", "1.5d", "1000d", "1000w", "25S", "4H", NULL, "0h", "42"};
    const double expected[] = {30, 0.01, 1.5, 90, 5400, 129600, 86400000, 604800000, 0.025, 14400, 0, 0, 0.042};
    for(i = 0; i != 13; i++)
        assert(fabs(VCL_parse_time_value(inputs[i]) - expected[i]) < EPSILON);
    printf("All unit tests on VCL_parse_time_value passed!\n");
}
#endif
