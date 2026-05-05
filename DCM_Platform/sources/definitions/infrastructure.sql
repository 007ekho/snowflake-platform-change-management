-- infrastructure.sql
-- Databases and warehouses for the analytics platform
-- Owned by Platform team, deployed via DCM

DEFINE DATABASE ANALYTICS{{env_suffix}}
  DATA_RETENTION_TIME_IN_DAYS = {{data_retention_days}}
  COMMENT = 'Analytics platform database for {{env_suffix}} environment';

DEFINE SCHEMA ANALYTICS{{env_suffix}}.RAW
  COMMENT = 'Raw ingestion layer';

DEFINE SCHEMA ANALYTICS{{env_suffix}}.STAGING
  COMMENT = 'Staging layer';

DEFINE SCHEMA ANALYTICS{{env_suffix}}.ANALYTICS
  COMMENT = 'Analytics layer';

DEFINE SCHEMA ANALYTICS{{env_suffix}}.SERVING
  COMMENT = 'Serving layer';

DEFINE WAREHOUSE PLATFORM_WH{{env_suffix}}
  WITH
    warehouse_size = '{{warehouse_size}}'
    auto_suspend = {{auto_suspend}}
    auto_resume = {{auto_resume}}
    comment = 'Platform warehouse - {{env_suffix}}';

DEFINE WAREHOUSE ANALYST_WH{{env_suffix}}
  WITH
    warehouse_size = 'XSMALL'
    auto_suspend = {{auto_suspend}}
    auto_resume = {{auto_resume}}
    comment = 'Analyst warehouse - {{env_suffix}}';