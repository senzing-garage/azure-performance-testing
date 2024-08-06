

Diagnostic runs:
20240703
=====================================================================================================
Platform:                       |       AWS      |       AWS      |       AWS      |     Azure      |
Build:                          |  3.10.1.24135  |  3.10.3-24163  |  3.10.4-24159  |  3.10.4-24184  |
Number of records:              |    25 M        |    25 M        |    25 M        |    25 M        |
Peak:                           |  2501          |  2404          |  5309          |    --          |
Warm-up:                        |    25 mins     |    29 mins     |    25 mins     |    -- mins     |
Average after warm-up:          |  2197          |  2139          |  4492          |    --          |
Average over entire run:        |  1937          |  1896          |  3530          |   423          |
Time to load 20M:               |     3.1 hours  |     3.2 hours  |     1.7 hours  |    13.35 hours |
Records in dead-letter queue:   |     0          |     0          |     0          |     0          |
Total Billed read IOPS:         |      607,778   |      149,894   |      508,216   |    --          |
Total Billed write IOPS:        |   99,726,985   |   96,757,579   |  100,824,689   |    --          |
Max loader tasks:               |     45         |     44         |    100         |    350         |
Max redoer tasks:               |     43         |     43         |     76         |     --         |
Notes:                          | single DB inst | single DB inst | single DB inst | single DB inst |
                                |   serverless   |   serverless   |   serverless   |  provisioned   |
=====================================================================================================

