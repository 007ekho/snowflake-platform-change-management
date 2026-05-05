-- raw_tables.sql
-- Raw ingestion tables - landing zone for source data
-- Owned by Platform team via DCM

DEFINE TABLE ANALYTICS{{env_suffix}}.RAW.orders (
  order_id     VARCHAR       NOT NULL  COMMENT 'Unique order identifier',
  customer_id  VARCHAR                 COMMENT 'Reference to customer',
  order_date   DATE                    COMMENT 'Date order was placed',
  amount       NUMBER(10,2)            COMMENT 'Order total value',
  status       VARCHAR(50)             COMMENT 'Order status: PENDING, COMPLETED, CANCELLED',
  region       VARCHAR(50)             COMMENT 'Geographic region',
  load_time    TIMESTAMP_LTZ           COMMENT 'When record was loaded',
  currency_code  VARCHAR(3)    COMMENT 'ISO currency code e.g. GBP, USD'  -- NEW
)
DATA_RETENTION_TIME_IN_DAYS = {{data_retention_days}}
COMMENT = 'Raw orders from source systems - do not transform here';

DEFINE TABLE ANALYTICS{{env_suffix}}.RAW.customers (
  customer_id   VARCHAR       NOT NULL  COMMENT 'Unique customer identifier',
  customer_name VARCHAR(200)            COMMENT 'Full customer name',
  email         VARCHAR(200)            COMMENT 'Customer email address',
  region        VARCHAR(50)             COMMENT 'Customer region',
  load_time     TIMESTAMP_LTZ           COMMENT 'When record was loaded'
)
DATA_RETENTION_TIME_IN_DAYS = {{data_retention_days}}
COMMENT = 'Raw customer master data - source of truth';

DEFINE TABLE ANALYTICS{{env_suffix}}.RAW.platform_audit_log (
  event_time   TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP() COMMENT 'When event occurred',
  event_type   VARCHAR(50)                                COMMENT 'Type of event',
  object_name  VARCHAR(200)                               COMMENT 'Object affected',
  performed_by VARCHAR(200)                               COMMENT 'Role that performed action',
  details      VARIANT                                    COMMENT 'Additional event details'
)
DATA_RETENTION_TIME_IN_DAYS = {{data_retention_days}}
COMMENT = 'Platform-level audit trail for compliance and debugging';
-- Products reference table
DEFINE TABLE ANALYTICS{{env_suffix}}.RAW.products (
  product_id   VARCHAR       NOT NULL  COMMENT 'Unique product identifier',
  product_name VARCHAR(200)            COMMENT 'Product display name',
  category     VARCHAR(100)            COMMENT 'Product category',
  unit_price   NUMBER(10,2)            COMMENT 'Standard unit price',
  load_time    TIMESTAMP_LTZ           COMMENT 'When record was loaded'
)
DATA_RETENTION_TIME_IN_DAYS = {{data_retention_days}}
COMMENT = 'Product catalogue reference data';
