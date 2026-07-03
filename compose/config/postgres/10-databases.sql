-- Create the per-service databases on first init (empty data dir only).
-- Each ShipGrid service owns one logical database and self-migrates its schema
-- on startup. The list must match the service images' built-in DSN defaults
-- (postgres://devflow:devflow@postgres:5432/devflow_<service>).
SELECT 'CREATE DATABASE devflow_admin_auth'         WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'devflow_admin_auth')\gexec
SELECT 'CREATE DATABASE devflow_ai_analysis'        WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'devflow_ai_analysis')\gexec
SELECT 'CREATE DATABASE devflow_ai_settings'        WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'devflow_ai_settings')\gexec
SELECT 'CREATE DATABASE devflow_auth'               WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'devflow_auth')\gexec
SELECT 'CREATE DATABASE devflow_billing'            WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'devflow_billing')\gexec
SELECT 'CREATE DATABASE devflow_delivery_ops'       WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'devflow_delivery_ops')\gexec
SELECT 'CREATE DATABASE devflow_dev_jobs'           WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'devflow_dev_jobs')\gexec
SELECT 'CREATE DATABASE devflow_gate'               WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'devflow_gate')\gexec
SELECT 'CREATE DATABASE devflow_indexing'           WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'devflow_indexing')\gexec
SELECT 'CREATE DATABASE devflow_platform'           WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'devflow_platform')\gexec
SELECT 'CREATE DATABASE devflow_qa_hub'             WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'devflow_qa_hub')\gexec
SELECT 'CREATE DATABASE devflow_review_processor'   WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'devflow_review_processor')\gexec
SELECT 'CREATE DATABASE devflow_security'           WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'devflow_security')\gexec
SELECT 'CREATE DATABASE devflow_task_tracker'       WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'devflow_task_tracker')\gexec
SELECT 'CREATE DATABASE devflow_webhook_ingestor'   WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'devflow_webhook_ingestor')\gexec
SELECT 'CREATE DATABASE devflow_cloud_scanner'      WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'devflow_cloud_scanner')\gexec
SELECT 'CREATE DATABASE devflow_policy_engine'      WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'devflow_policy_engine')\gexec
SELECT 'CREATE DATABASE devflow_proof_engine'       WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'devflow_proof_engine')\gexec
SELECT 'CREATE DATABASE devflow_runtime_collector'  WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'devflow_runtime_collector')\gexec
SELECT 'CREATE DATABASE devflow_k8s_scanner'        WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'devflow_k8s_scanner')\gexec
SELECT 'CREATE DATABASE devflow_findings_correlator' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'devflow_findings_correlator')\gexec
