# azure-test-results-20240703-25M-senzing-3.10.4

## Contents

1. [Overview](#overview)
1. [Results](#results)
    1. [Observations](#observations)
    1. [Final metrics](#final-metrics)
        1. [Service Bus](#service-bus)
        1. [AKS](#aks)
        1. [RDS](#rds)
        1. [Logs](#logs)

## Overview

1. Performed: Jul 03, 2024
2. Senzing version: 3.10.4.24184
3. Instructions:
   [azure-performance-testing](https://github.com/senzing-garage/azure-performance-testing)
    1. [Terraform and AKS](https://github.com/senzing-garage/azure-performance-testing/tree/main/perf.tf)
4. Changes:
    1.

## System

1. Database
    1. Azure SQL
    1. Hyperscale: Gen5, 32 vCores
    1. Single database

## Results

### Observations

1. Inserts per second:
    1. Average over entire run: 423/second
    1. Time to load 25M: 13.35 hours
    1. Records in dead-letter queue: 0

Note:  Withinfo disabled.

- Max Stream-loader tasks: 350
- Max Redoer tasks: --

### Final metrics

#### Service Bus

##### Service bus queue metrics

![Service bus metrics](images/service-bus.png "Service bus metrics")

#### AKS

##### AKS CPU

![AKS CPU Utilization](images/k8s-cpu.png "AKS CPU Utilization")

##### AKS nodes metrics

![AKS nodes metrics](images/k8s-nodes.png "AKS nodes metrics")

#### RDS

##### Azure SQL database Metrics

![Database metrics - average compute](images/azure-sql-average-compute.png "Database metrics average compute")
![Database metrics - CPU](images/azure-sql-cpu.png "Database metrics - CPU")
![Database metrics - data IO](images/azure-sql-data-io.png "Database metrics - data IO")

#### Logs

```
root@sz-tools-6bf876bb9d-gwp9l:/# sqlcmd -S $AZURE_ANIMAL-mssql-server.database.windows.net -d G2 -U senzing -P "$SENZING_DB_PWD" -I  -Q "SELECT GETDATE(), COUNT(*) FROM DSRC_RECORD;"

----------------------- -----------
2024-07-04 12:11:26.903    20347400

(1 rows affected)
root@sz-tools-6bf876bb9d-gwp9l:/# sqlcmd -S $AZURE_ANIMAL-mssql-server.database.windows.net -d G2 -U senzing -P "$SENZING_DB_PWD" -I  -Q "SELECT GETDATE(), COUNT(*) FROM OBS_ENT;"

----------------------- -----------
2024-07-04 12:16:25.510    19840129

(1 rows affected)
root@sz-tools-6bf876bb9d-gwp9l:/# sqlcmd -S $AZURE_ANIMAL-mssql-server.database.windows.net -d G2 -U senzing -P "$SENZING_DB_PWD" -I  -Q "SELECT GETDATE(), COUNT(*) FROM RES_ENT;"

----------------------- -----------
2024-07-04 12:16:34.103    17056844

(1 rows affected)
root@sz-tools-6bf876bb9d-gwp9l:/# sqlcmd -S $AZURE_ANIMAL-mssql-server.database.windows.net -d G2 -U senzing -P "$SENZING_DB_PWD" -I  -Q "SELECT GETDATE(), COUNT(*) FROM RES_ENT_OKEY;"

----------------------- -----------
2024-07-04 12:16:45.120    19840129

(1 rows affected)
root@sz-tools-6bf876bb9d-gwp9l:/# sqlcmd -S $AZURE_ANIMAL-mssql-server.database.windows.net -d G2 -U senzing -P "$SENZING_DB_PWD" -I  -Q "SELECT GETDATE(), COUNT(*) FROM SYS_EVAL_QUEUE;"

----------------------- -----------
2024-07-04 12:17:15.477           2

(1 rows affected)
root@sz-tools-6bf876bb9d-gwp9l:/# sqlcmd -S $AZURE_ANIMAL-mssql-server.database.windows.net -d G2 -U senzing -P "$SENZING_DB_PWD" -I  -Q "SELECT GETDATE(), COUNT(*) FROM RES_RELATE;"

----------------------- -----------
2024-07-04 12:17:27.107     9928767

(1 rows affected)
root@sz-tools-6bf876bb9d-gwp9l:/# sqlcmd -S $AZURE_ANIMAL-mssql-server.database.windows.net -d G2 -U senzing -P "$SENZING_DB_PWD" -I  -Q "select min(first_seen_dt) load_start, count(*)/(DATEDIFF_BIG(SECOND, min(first_seen_dt), max(first_seen_dt))/60) erpm, count(*) total, max(first_seen_dt)-min(first_seen_dt) duration, count(*)/DATEDIFF_BIG(SECOND, min(first_seen_dt), max(first_seen_dt)) avg_erps from dsrc_record;"
load_start              erpm                 total       duration                avg_erps
----------------------- -------------------- ----------- ----------------------- --------------------
2024-07-03 17:13:43.037                25402    20347400 1900-01-01 13:21:06.513                  423

(1 rows affected)
root@sz-tools-6bf876bb9d-gwp9l:/# sqlcmd -S $AZURE_ANIMAL-mssql-server.database.windows.net -d G2 -U senzing -P "$SENZING_DB_PWD" -I  -Q "select dr.RECORD_ID,oe.OBS_ENT_ID,reo.RES_ENT_ID from DSRC_RECORD dr left outer join OBS_ENT oe ON dr.dsrc_id = oe.dsrc_id and dr.ent_src_key = oe.ent_src_key left outer join RES_ENT_OKEY reo ON oe.OBS_ENT_ID = reo.OBS_ENT_ID where reo.RES_ENT_ID is null;"
RECORD_ID                                                                                                                                                                                                                                                  OBS_ENT_ID           RES_ENT_ID
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- -------------------- --------------------

(0 rows affected)
root@sz-tools-6bf876bb9d-gwp9l:/# sqlcmd -S $AZURE_ANIMAL-mssql-server.database.windows.net -d G2 -U senzing -P "$SENZING_DB_PWD" -I  -Q "select dr.RECORD_ID,reo.OBS_ENT_ID,reo.RES_ENT_ID from RES_ENT_OKEY reo left outer join OBS_ENT oe ON oe.OBS_ENT_ID = reo.OBS_ENT_ID  left outer join DSRC_RECORD dr  ON dr.dsrc_id = oe.dsrc_id and dr.ent_src_key = oe.ent_src_key where dr.RECORD_ID is null;"
RECORD_ID                                                                                                                                                                                                                                                  OBS_ENT_ID           RES_ENT_ID
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- -------------------- --------------------

(0 rows affected)
```
