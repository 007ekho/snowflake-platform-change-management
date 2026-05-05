-- scripts/create_streams.sql
-- Streams cannot be managed by DCM Projects (not yet supported)
-- Run after DCM deployment

USE ROLE PLATFORM_DCM_ROLE;

CREATE STREAM IF NOT EXISTS ANALYTICS_DEV.RAW.orders_stream
  ON TABLE ANALYTICS_DEV.RAW.ORDERS
  COMMENT = 'CDC stream tracking all order changes';

CREATE STREAM IF NOT EXISTS ANALYTICS_DEV.RAW.customers_stream
  ON TABLE ANALYTICS_DEV.RAW.CUSTOMERS
  COMMENT = 'CDC stream tracking customer changes';