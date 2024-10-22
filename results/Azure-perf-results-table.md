

20241021
====================================================================================
Platform:                       |       AWS      |     Azure      |     Azure      |
Build:                          |  3.12.1.24295  |  3.12.1-24281  |  3.12.1-24295  |
Number of records:              |    25 M        |    25 M        |    25 M        |
Number of records loaded:       | 21645223       | 21622221       | 21622221       |
Peak:                           |  2049          |    --          |    --          |
Warm-up:                        |    15 mins     |    -- mins     |    -- mins     |
Average after warm-up:          |  1690          |    --          |    --          |
Average over entire run:        |  1612          |   324          |   336          |
Time to load 20M:               |     3.73 hours |    18.52 hours |    17.87 hours |
Records in dead-letter queue:   |     0          |     0          |     0          |
Total Billed read IOPS:         |      574,897   |    --          |    --          |
Total Billed write IOPS:        |   99,307,108   |    --          |    --          |
Max loader tasks:               |     36         |     50         |     50         |
Max redoer tasks:               |     37         |     --         |     11         |
Notes:                          | single DB inst | single DB inst | single DB inst |
                                |   serverless   |  provisioned   |  provisioned   |
====================================================================================

20241007
=====================================================================================================
Platform:                       |       AWS      |     Azure      |       AWS      |     Azure      |
Build:                          |  3.10.4-24184  |  3.10.4-24184  |  3.12.1-24281  |  3.12.1-24281  |
Number of records:              |    25 M        |    25 M        |    25 M        |    25 M        |
Number of records loaded:       | 21645223       | 21645223       | 21645223       | 21622221       |
Peak:                           |  2382          |    --          |  2049          |    --          |
Warm-up:                        |    31 mins     |    -- mins     |    29 mins     |    -- mins     |
Average after warm-up:          |  2025          |    --          |  1816          |    --          |
Average over entire run:        |  1776          |   423          |  1659          |   324          |
Time to load 20M:               |     3.4 hours  |    13.35 hours |     3.62 hours |    18.52 hours |
Records in dead-letter queue:   |     0          |     0          |     0          |     0          |
Total Billed read IOPS:         |       18,904   |    --          |      576,546   |    --          |
Total Billed write IOPS:        |   96,558,504   |    --          |   98,743,472   |    --          |
Max loader tasks:               |     42         |    350         |     38         |     50         |
Max redoer tasks:               |     43         |     --         |     38         |     --         |
Notes:                          | single DB inst | single DB inst | single DB inst | single DB inst |
                                |   serverless   |  provisioned   |   serverless   |  provisioned   |
=====================================================================================================




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

