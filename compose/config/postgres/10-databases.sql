-- Per-service databases on the bundled single-node Postgres. Runs once, on an
-- empty data dir (docker-entrypoint-initdb.d). Each service self-migrates its
-- own schema on startup; the names match the per-service DATABASE_URL / config
-- DSNs in the compose file (postgres://shipgrid:shipgrid@postgres:5432/<db>).
SELECT 'CREATE DATABASE shipgrid_admin_auth'         WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'shipgrid_admin_auth')\gexec
SELECT 'CREATE DATABASE shipgrid_ai_analysis'        WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'shipgrid_ai_analysis')\gexec
SELECT 'CREATE DATABASE shipgrid_ai_settings'        WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'shipgrid_ai_settings')\gexec
SELECT 'CREATE DATABASE shipgrid_auth'               WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'shipgrid_auth')\gexec
SELECT 'CREATE DATABASE shipgrid_billing'            WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'shipgrid_billing')\gexec
SELECT 'CREATE DATABASE shipgrid_delivery_ops'       WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'shipgrid_delivery_ops')\gexec
SELECT 'CREATE DATABASE shipgrid_dev_jobs'           WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'shipgrid_dev_jobs')\gexec
SELECT 'CREATE DATABASE shipgrid_gate'               WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'shipgrid_gate')\gexec
SELECT 'CREATE DATABASE shipgrid_indexing'           WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'shipgrid_indexing')\gexec
SELECT 'CREATE DATABASE shipgrid_platform'           WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'shipgrid_platform')\gexec
SELECT 'CREATE DATABASE shipgrid_qa_hub'             WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'shipgrid_qa_hub')\gexec
SELECT 'CREATE DATABASE shipgrid_review_processor'   WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'shipgrid_review_processor')\gexec
SELECT 'CREATE DATABASE shipgrid_security'           WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'shipgrid_security')\gexec
SELECT 'CREATE DATABASE shipgrid_task_tracker'       WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'shipgrid_task_tracker')\gexec
SELECT 'CREATE DATABASE shipgrid_webhook_ingestor'   WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'shipgrid_webhook_ingestor')\gexec
-- security split-workers (each owns its own DB)
SELECT 'CREATE DATABASE shipgrid_cloud_scanner'      WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'shipgrid_cloud_scanner')\gexec
SELECT 'CREATE DATABASE shipgrid_policy_engine'      WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'shipgrid_policy_engine')\gexec
SELECT 'CREATE DATABASE shipgrid_proof_engine'       WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'shipgrid_proof_engine')\gexec
SELECT 'CREATE DATABASE shipgrid_runtime_collector'  WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'shipgrid_runtime_collector')\gexec
SELECT 'CREATE DATABASE shipgrid_k8s_scanner'        WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'shipgrid_k8s_scanner')\gexec
SELECT 'CREATE DATABASE shipgrid_findings_correlator' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'shipgrid_findings_correlator')\gexec
