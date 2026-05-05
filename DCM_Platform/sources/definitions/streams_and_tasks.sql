-- -- streams_and_tasks.sql
-- -- CDC streams and scheduled tasks
-- -- Deployed alongside the tables they depend on - correct ownership

-- -- Stream: captures all changes to orders table
-- DEFINE STREAM ANALYTICS{{env_suffix}}.RAW.orders_stream
--   ON TABLE ANALYTICS{{env_suffix}}.RAW.orders
--   COMMENT = 'CDC stream tracking all order changes for downstream processing';

-- -- Stream: captures all changes to customers table
-- DEFINE STREAM ANALYTICS{{env_suffix}}.RAW.customers_stream
--   ON TABLE ANALYTICS{{env_suffix}}.RAW.customers
--   COMMENT = 'CDC stream tracking customer record changes';

-- -- Root task: processes new orders when stream has data
-- DEFINE TASK ANALYTICS{{env_suffix}}.RAW.process_new_orders
--   WAREHOUSE = PLATFORM_WH{{env_suffix}}
--   SCHEDULE  = 'USING CRON */5 * * * * Europe/London'
--   WHEN      SYSTEM$STREAM_HAS_DATA('ANALYTICS{{env_suffix}}.RAW.orders_stream')
--   COMMENT   = 'Root task: processes new orders from CDC stream into staging'
-- AS
--   INSERT INTO ANALYTICS{{env_suffix}}.RAW.platform_audit_log
--     (event_type, object_name, performed_by, details)
--   SELECT
--     METADATA$ACTION,
--     'ANALYTICS{{env_suffix}}.RAW.orders',
--     CURRENT_ROLE(),
--     OBJECT_CONSTRUCT(
--       'order_id', order_id,
--       'status', status,
--       'event_time', CURRENT_TIMESTAMP()
--     )
--   FROM ANALYTICS{{env_suffix}}.RAW.orders_stream;

-- -- Child task: runs after orders processed
-- DEFINE TASK ANALYTICS{{env_suffix}}.RAW.log_pipeline_complete
--   WAREHOUSE = PLATFORM_WH{{env_suffix}}
--   AFTER ANALYTICS{{env_suffix}}.RAW.process_new_orders
--   COMMENT = 'Child task: logs pipeline completion to audit trail'
-- AS
--   INSERT INTO ANALYTICS{{env_suffix}}.RAW.platform_audit_log
--     (event_type, object_name, performed_by)
--   VALUES
--     ('PIPELINE_COMPLETE', 'process_new_orders', CURRENT_ROLE());


-- streams_and_tasks.sql
-- Scheduled tasks for platform data processing
-- NOTE: Streams not supported by DCM - managed via scripts/create_streams.sql

-- Root task: processes new orders on schedule
DEFINE TASK ANALYTICS{{env_suffix}}.RAW.process_new_orders
  WAREHOUSE = PLATFORM_WH{{env_suffix}}
  SCHEDULE  = 'USING CRON */5 * * * * Europe/London'
AS
  INSERT INTO ANALYTICS{{env_suffix}}.RAW.platform_audit_log
    (event_type, object_name, performed_by)
  VALUES
    ('TASK_RUN', 'process_new_orders', CURRENT_ROLE());

-- Child task: runs after root task completes
DEFINE TASK ANALYTICS{{env_suffix}}.RAW.log_pipeline_complete
  WAREHOUSE = PLATFORM_WH{{env_suffix}}
  AFTER ANALYTICS{{env_suffix}}.RAW.process_new_orders
AS
  INSERT INTO ANALYTICS{{env_suffix}}.RAW.platform_audit_log
    (event_type, object_name, performed_by)
  VALUES
    ('PIPELINE_COMPLETE', 'process_new_orders', CURRENT_ROLE());