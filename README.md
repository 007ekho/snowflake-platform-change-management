# Snowflake Platform Database Change Management

> **Production-grade schema-level object management using Snowflake's native DCM Projects**

[![Snowflake DCM](https://img.shields.io/badge/Snowflake-DCM%20Projects-29B5E8?style=flat&logo=snowflake)](https://docs.snowflake.com/en/user-guide/dcm-projects/dcm-projects-overview)
[![CI/CD](https://img.shields.io/badge/CI%2FCD-GitHub%20Actions-2088FF?style=flat&logo=github-actions)](https://github.com/features/actions)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

---

## Table of Contents

- [What This Project Does](#what-this-project-does)
- [Why This Exists - The Business Case](#why-this-exists---the-business-case)
- [Why DCM Projects and Not Terraform](#why-dcm-projects-and-not-terraform)
- [Architecture](#architecture)
- [Three-Repo Platform Model](#three-repo-platform-model)
- [Project Structure](#project-structure)
- [What Gets Deployed](#what-gets-deployed)
- [Environments](#environments)
- [The Deployment Workflow](#the-deployment-workflow)
- [Lessons Learned](#lessons-learned)
- [Getting Started](#getting-started)
- [Key Commands](#key-commands)

---

## What This Project Does

This repository manages all **schema-level Snowflake objects** as code using Snowflake's native **Database Change Management (DCM) Projects**. Every database, schema, table, warehouse and task in the analytics platform is defined in version-controlled SQL files and deployed automatically through a CI/CD pipeline.

**In plain terms:** Instead of someone manually creating tables and warehouses by clicking around in Snowflake, this system does it automatically. Every change is reviewed before it's applied, every deployment is recorded, and nothing ever touches production without going through a review process.

---

## Why This Exists - The Business Case

### The Problem Before This System

In most organisations without platform automation:

```
New project needs a table
        ↓
Someone logs into Snowflake manually
        ↓
Clicks around to create the table
        ↓
No record of who created it or why
        ↓
No consistency across dev, staging and prod
        ↓
Schema drift: environments look different
        ↓
"Works on dev, broken in prod"
```

This creates three business risks:

**1. Compliance Risk** — No audit trail of who changed what and when. Regulators require evidence of change control, especially in healthcare and finance.

**2. Reliability Risk** — Manual changes cause inconsistency between environments. What works in dev may not work in staging or production.

**3. Cost Risk** — Manual processes are slow, error-prone and require senior engineers for routine tasks. Automation frees engineers to work on higher-value problems.

### What This System Delivers

```
Engineer proposes a change (adds a table)
        ↓
Pull request created on GitHub
        ↓
Pipeline automatically shows exactly what will change
        ↓
Team reviews and approves
        ↓
Merge triggers automatic deployment
        ↓
Full audit trail in Git history
        ↓
Consistent across all environments
```

**Business outcomes:**
- ✅ Full audit trail for compliance
- ✅ Peer review before any change reaches production
- ✅ Consistent environments across dev, staging and production
- ✅ Faster onboarding — new environments deployed in minutes not days
- ✅ Reduced toil — routine infrastructure changes are automated

---

## Why DCM Projects and Not Terraform

This is the most important architectural decision in this project. The short answer: **Snowflake's own documentation recommends DCM Projects for schema-level objects**. Here is the full explanation.

### Terraform's Limitations for Schema Objects

Terraform is an excellent tool for cloud infrastructure — it manages AWS resources, network configurations and account-level Snowflake settings extremely well. However it has fundamental limitations when managing schema-level Snowflake objects:

**Problem 1: Data Loss on Schema Changes**

When you change a table definition in Terraform, it compares the desired state to the current state and determines the simplest path to get there. For tables, that path is often DROP and recreate:

```
You add a column to a Terraform table definition
        ↓
Terraform sees: "current table != desired table"
        ↓
Terraform drops the table
        ↓
Terraform creates a new table with the new column
        ↓
ALL DATA IS GONE
```

DCM Projects understand Snowflake's data model and generate an ALTER TABLE instead:

```
You add a column to a DCM table definition
        ↓
DCM sees: "table exists, needs a new column"
        ↓
DCM generates: ALTER TABLE orders ADD COLUMN currency_code VARCHAR(3)
        ↓
Data preserved, column added safely
```

**Problem 2: State Drift from Other Tools**

In production, multiple tools touch Snowflake objects. dbt creates and modifies tables as part of transformation pipelines. Airbyte adds columns when source schemas change. Snowpipe evolves tables as data arrives. Terraform has no knowledge of any of these changes. Its state file becomes stale and plans become unreliable:

```
dbt runs and adds a column to a table
        ↓
Terraform state still shows old table definition
        ↓
Next terraform plan: "I need to remove that column"
        ↓
Dangerous: Terraform would destroy dbt's work
```

DCM Projects are stateless by design — they always compare against what actually exists in Snowflake, not a cached state file.

**Problem 3: Tasks and Streams Depend on Tables They Don't Own**

Tasks and streams are schema-level objects that depend on tables owned by other tools. Managing them in Terraform creates a fragile dependency chain:

```
Terraform manages: tasks and streams
dbt manages: tables that tasks reference

dbt does a full refresh → drops and recreates tables
Streams become invalid
Terraform state thinks streams still exist
Next apply fails with cryptic errors
```

By managing tasks alongside their dependent tables in DCM, the ownership boundary is clean.

### The Snowflake Documentation Position

Snowflake's own DevOps documentation states:

> *"The recommended approach is to use DCM Projects (Database Change Management Projects), which unify declarative object management, plan-then-deploy validation, multi-environment targeting, and CI/CD automation into a single workflow."*

Snowflake built DCM specifically because they recognised that generic IaC tools lack the Snowflake-specific intelligence needed to safely manage schema-level objects.

### Decision Summary

| Concern | Terraform | Snowflake DCM |
|---------|-----------|---------------|
| Adding a column | May DROP and recreate (data loss) | Generates ALTER TABLE (safe) |
| State management | File-based, gets stale | Always compares against live Snowflake |
| Dependency resolution | Manual `depends_on` everywhere | Automatic |
| Tasks referencing tables | Fragile cross-tool dependency | Same tool, clean ownership |
| Multi-environment config | Complex tfvars + workspaces | Native Jinja templating |
| Recommended by Snowflake | For infrastructure only | For all schema objects |
| Provider lag | Often behind new Snowflake features | Always current |

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                     PLATFORM ENGINEERING STACK                       │
│                                                                       │
│  ┌─────────────────┐    ┌──────────────────┐    ┌────────────────┐  │
│  │   TERRAFORM      │    │   SNOWFLAKE DCM   │    │  SQL SCRIPTS   │  │
│  │  (RBAC Repo)     │    │   (This Repo)     │    │  (Post-Deploy) │  │
│  │                  │    │                   │    │                │  │
│  │  • Roles         │    │  • Databases      │    │  • Streams     │  │
│  │  • Users         │    │  • Schemas        │    │   (DCM does    │  │
│  │  • Grants        │    │  • Tables         │    │    not yet     │  │
│  │  • Warehouses*   │    │  • Warehouses     │    │    support     │  │
│  │  • Resource      │    │  • Tasks (DAG)    │    │    streams)    │  │
│  │    Monitors      │    │  • Dynamic Tables │    │                │  │
│  │  • Network       │    │  • Views          │    │                │  │
│  │    Policies      │    │                   │    │                │  │
│  └────────┬─────────┘    └────────┬──────────┘    └───────┬────────┘  │
│           │                       │                        │           │
│           └───────────────────────┴────────────────────────┘           │
│                                   │                                     │
│                                   ▼                                     │
│                         ┌──────────────────┐                           │
│                         │    SNOWFLAKE      │                           │
│                         │                   │                           │
│                         │  ANALYTICS_DEV    │                           │
│                         │  ANALYTICS_STAG   │                           │
│                         │  ANALYTICS_PROD   │                           │
│                         └──────────────────┘                           │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## CI/CD Pipeline Flow

```
Developer makes change (e.g. adds a table)
              │
              ▼
    git checkout -b feature/my-change
    Edit definition file
    git push origin feature/my-change
              │
              ▼
    ┌─────────────────────────────────┐
    │     CREATE PULL REQUEST          │
    │     Base: main                   │
    │     Compare: feature/my-change   │
    └─────────────────┬───────────────┘
                      │
                      ▼
    ┌─────────────────────────────────┐
    │     GITHUB ACTIONS TRIGGERS      │
    │                                  │
    │  1. Install Snowflake CLI        │
    │  2. Create config dynamically    │
    │  3. Inject secrets from          │
    │     GitHub Secrets               │
    │  4. Run: snow dcm plan           │
    └─────────────────┬───────────────┘
                      │
                      ▼
    ┌─────────────────────────────────┐
    │     DCM PLAN OUTPUT              │
    │     Posted as PR comment:        │
    │                                  │
    │  CREATE TABLE ANALYTICS_DEV      │
    │    .RAW.PRODUCTS                 │
    │  ALTER TABLE ANALYTICS_DEV       │
    │    .RAW.ORDERS                   │
    │    ADD COLUMN currency_code      │
    │                                  │
    │  2 to create, 1 to alter,        │
    │  0 to drop                       │
    └─────────────────┬───────────────┘
                      │
                      ▼
    ┌─────────────────────────────────┐
    │     PEER REVIEW                  │
    │                                  │
    │  Team reviews exactly what       │
    │  will change before approving    │
    └─────────────────┬───────────────┘
                      │
                      ▼
              MERGE PULL REQUEST
                      │
                      ▼
    ┌─────────────────────────────────┐
    │     GITHUB ACTIONS TRIGGERS      │
    │                                  │
    │  1. Install Snowflake CLI        │
    │  2. Create config dynamically    │
    │  3. Inject secrets               │
    │  4. Run: snow dcm deploy         │
    └─────────────────┬───────────────┘
                      │
                      ▼
    ┌─────────────────────────────────┐
    │     SNOWFLAKE UPDATED            │
    │                                  │
    │  ✅ Table created                │
    │  ✅ Column added (ALTER, not     │
    │     DROP - data preserved)       │
    └─────────────────────────────────┘
```

---

## Three-Repo Platform Model

This repository is one part of a three-repo platform architecture. Each repo owns a specific layer with clear boundaries:

| Repository | Tool | Owns | Why |
|------------|------|------|-----|
| [Terraform-Snowflake-RBAC-Automation](https://github.com/007ekho/Terraform-Snowflake-RBAC-Automation) | Terraform | Roles, users, grants, resource monitors, network policies | Account-level infrastructure — stable objects where Terraform's declarative state model works reliably |
| **This repo** | Snowflake DCM | Databases, schemas, tables, warehouses, tasks | Schema-level objects — Snowflake-native tooling that understands data model semantics |
| [Multi-Tenant-Clinical-Data-Governance-Platform](https://github.com/007ekho/Multi-Tenant-Clinical-Data-Governance-Platform) | SQL | Masking policies, row-level security, HIPAA compliance | Governance layer — data protection policies applied across the platform |

**Why three repos and not one?**

Each layer has different ownership, different change frequency and different risk profile:

- **RBAC changes** are infrequent, high-risk and need careful review. Terraform's plan/apply with state management suits this well.
- **Schema changes** are frequent, need data-safe ALTER operations and must coexist with dbt and other tools. DCM suits this.
- **Governance changes** affect data access and regulatory compliance. They deserve their own review process.

---

## Project Structure

```
snowflake-platform-change-management/
│
├── .github/
│   └── workflows/
│       └── dcm-pipeline.yml          ← CI/CD pipeline
│                                        Plan on PR, Deploy on merge
│
├── DCM_Platform/                     ← Main DCM project
│   ├── manifest.yml                  ← Environment targets + Jinja config
│   │                                    DEV / STAGING / PROD
│   │
│   └── sources/
│       ├── definitions/              ← DCM manages everything here
│       │   ├── infrastructure.sql    ← Databases, schemas, warehouses
│       │   ├── raw_tables.sql        ← Raw ingestion layer tables
│       │   └── streams_and_tasks.sql ← Scheduled task DAG
│       │
│       └── macros/
│           └── grants_macro.sql      ← Reusable Jinja macros
│
├── scripts/                          ← Run outside DCM (post-deploy)
│   └── create_streams.sql            ← Streams (not yet supported by DCM)
│
├── .gitignore                        ← Excludes DCM output artifacts
└── README.md
```

---

## What Gets Deployed

### Managed by DCM (12 objects)

| Object | Name | Purpose |
|--------|------|---------|
| DATABASE | ANALYTICS_DEV | Analytics platform database |
| SCHEMA | ANALYTICS_DEV.RAW | Raw ingestion landing zone |
| SCHEMA | ANALYTICS_DEV.STAGING | Cleaned and conformed data |
| SCHEMA | ANALYTICS_DEV.ANALYTICS | Business-level aggregations |
| SCHEMA | ANALYTICS_DEV.SERVING | BI-ready outputs |
| TABLE | ANALYTICS_DEV.RAW.ORDERS | Raw orders from source systems |
| TABLE | ANALYTICS_DEV.RAW.CUSTOMERS | Raw customer master data |
| TABLE | ANALYTICS_DEV.RAW.PRODUCTS | Product catalogue reference |
| TABLE | ANALYTICS_DEV.RAW.PLATFORM_AUDIT_LOG | Platform operations audit trail |
| WAREHOUSE | PLATFORM_WH_DEV | Platform processing compute |
| WAREHOUSE | ANALYST_WH_DEV | Analyst query compute (isolated) |
| TASK | PROCESS_NEW_ORDERS | Root task — scheduled pipeline |
| TASK | LOG_PIPELINE_COMPLETE | Child task — audit logging |

### Managed via Post-Deploy Script (2 objects)

| Object | Name | Why Not DCM |
|--------|------|-------------|
| STREAM | ORDERS_STREAM | Streams not yet supported by DCM Projects |
| STREAM | CUSTOMERS_STREAM | Tracked as known limitation, scripts/create_streams.sql |

---

## Environments

The same definition files deploy to all three environments using Jinja templating. Environment-specific values are defined in `manifest.yml`:

| Setting | DEV | STAGING | PROD |
|---------|-----|---------|------|
| Database suffix | `_DEV` | `_STAGING` | `_PROD` |
| Platform warehouse size | XSMALL | SMALL | MEDIUM |
| Auto-suspend | 60 seconds | 120 seconds | 300 seconds |
| Data retention | 1 day | 7 days | 30 days |

**How templating works:**

```sql
-- Definition file uses variables:
DEFINE DATABASE ANALYTICS{{env_suffix}}
  DATA_RETENTION_TIME_IN_DAYS = {{data_retention_days}};

-- DCM substitutes values per environment:
-- DEV:     CREATE DATABASE ANALYTICS_DEV (retention: 1 day)
-- STAGING: CREATE DATABASE ANALYTICS_STAGING (retention: 7 days)
-- PROD:    CREATE DATABASE ANALYTICS_PROD (retention: 30 days)
```

---

## The Deployment Workflow

### On Pull Request (Plan)

```yaml
Trigger: PR opened or updated targeting main
         AND files changed in DCM_Platform/**

Action:
  1. Install Snowflake CLI 3.16+
  2. Create ~/.snowflake/config.toml dynamically
  3. Connect using GitHub Secrets (never stored locally)
  4. Run: snow dcm plan --target DEV
  5. Post changeset as PR comment
```

### On Merge to Main (Deploy)

```yaml
Trigger: Push to main branch
         AND files changed in DCM_Platform/**

Action:
  1. Install Snowflake CLI 3.16+
  2. Create config dynamically
  3. Connect using GitHub Secrets
  4. Run: snow dcm deploy --target DEV
  5. Snowflake applies only the necessary changes
```

### Security Model

```
Developer's laptop     GitHub Secrets      GitHub Actions Runner
──────────────────     ──────────────      ─────────────────────
Has NO credentials  →  Stores encrypted →  Injects at runtime
                       credentials         as env variables
                                               │
                                               ▼
                                          Config created
                                          dynamically
                                               │
                                               ▼
                                          Snowflake CLI
                                          connects
                                               │
                                               ▼
                                          Job completes
                                          Config gone
```

No credentials ever touch a developer's machine. No secrets are ever committed to Git.

---

## Lessons Learned

Building this project surfaced important real-world lessons that aren't in documentation:

### 1. DCM Does Not Support Streams (Yet)

Streams are not in DCM's supported object types list. The project silently ignores `DEFINE STREAM` statements without erroring. The workaround is a post-deploy SQL script managed separately. This is a known DCM limitation and streams are likely to be added in a future release.

**Lesson:** Always verify against the [supported object types list](https://docs.snowflake.com/en/user-guide/dcm-projects/dcm-projects-supported-entities) before building.

---

### 2. Tasks Referencing Streams Need Two-Pass Deployment

When tasks reference streams in their `WHEN` clause, and those streams don't yet exist, DCM silently skips the tasks in the plan. The solution is to deploy infrastructure first, create streams via script, then tasks deploy cleanly on the next run.

**Lesson:** Plan your deployment order. Objects with dependencies need their dependencies to exist first.

---

### 3. DCM Only Supports Adding Columns at the End

When adding a column to a table, it must be placed at the end of the column list. Inserting a column in the middle triggers:

```
Unsupported feature 'CREATE OR ALTER TABLE column add before end of column list'
```

This is a Snowflake `CREATE OR ALTER` constraint, not a DCM limitation. Design column ordering thoughtfully upfront.

**Lesson:** Treat column ordering as an architectural decision. Use views for logical ordering rather than reordering physical columns.

---

### 4. Config File Permissions Matter

Snowflake CLI enforces `chmod 0600` on the config file. A file with wider permissions causes a hard error. The CI/CD pipeline must explicitly set permissions after creating the config file:

```bash
chmod 0600 ~/.snowflake/config.toml
```

**Lesson:** Security controls exist at the tooling level, not just the application level.

---

### 5. `--config-file` is a Global Flag

Snowflake CLI's `--config-file` flag must come before the subcommand:

```bash
# Wrong:
snow dcm plan --config-file config.toml

# Correct:
snow --config-file config.toml dcm plan
```

**Lesson:** Always check `snow --help` not `snow dcm plan --help` for global flags.

---

### 6. Never Depend on Local Files in CI/CD

The original design used a `.snowflake/config.toml` committed to the repository. This failed in CI/CD because the file path assumed a local machine context. The production-grade solution creates the config file dynamically at runtime:

```bash
mkdir -p ~/.snowflake
cat > ~/.snowflake/config.toml << 'EOF'
[connections.cicd]
EOF
chmod 0600 ~/.snowflake/config.toml
```

**Lesson:** Anything a pipeline needs that isn't in the repository should be created at runtime from secrets. Never assume local machine context.

---

### 7. Two-Pass Deployment Is Normal for DCM

DCM plans what it can see. If dependencies don't exist yet (warehouse not created, table not exists), dependent objects are skipped in that plan pass. Deploy the base layer first, then run plan again to pick up dependent objects.

**Lesson:** For complex environments, plan → deploy → plan → deploy is expected. DCM's dependency resolution handles ordering within a single pass for objects it can see, but cross-pass dependencies require multiple deployments.

---

## Getting Started

### Prerequisites

- Snowflake account (DCM Projects available on AWS, Azure and GCP)
- Snowflake CLI 3.16+ installed
- GitHub account
- Role with `CREATE DCM PROJECT ON SCHEMA` privilege

### Step 1: Snowflake Prerequisites

```sql
USE ROLE ACCOUNTADMIN;

CREATE DATABASE IF NOT EXISTS DCM_ADMIN;
CREATE SCHEMA IF NOT EXISTS DCM_ADMIN.PROJECTS;

CREATE ROLE IF NOT EXISTS PLATFORM_DCM_ROLE;

GRANT USAGE ON DATABASE DCM_ADMIN TO ROLE PLATFORM_DCM_ROLE;
GRANT USAGE ON SCHEMA DCM_ADMIN.PROJECTS TO ROLE PLATFORM_DCM_ROLE;
GRANT CREATE DCM PROJECT ON SCHEMA DCM_ADMIN.PROJECTS TO ROLE PLATFORM_DCM_ROLE;
GRANT USAGE ON WAREHOUSE COMPUTE_WH TO ROLE PLATFORM_DCM_ROLE;
GRANT CREATE DATABASE ON ACCOUNT TO ROLE PLATFORM_DCM_ROLE;
GRANT CREATE WAREHOUSE ON ACCOUNT TO ROLE PLATFORM_DCM_ROLE;

GRANT ROLE PLATFORM_DCM_ROLE TO USER YOUR_USERNAME;
```

### Step 2: Configure Snowflake CLI

```bash
snow connection add
# Follow prompts with your Snowflake account details

snow connection test --connection your_connection_name
```

### Step 3: Create DCM Project Object

```bash
snow dcm create \
  --target DEV \
  --from DCM_Platform/ \
  --connection your_connection_name \
  --role PLATFORM_DCM_ROLE
```

### Step 4: Plan and Deploy

```bash
# See what will be created
snow dcm plan \
  --target DEV \
  --from DCM_Platform/ \
  --connection your_connection_name \
  --role PLATFORM_DCM_ROLE

# Deploy if plan looks correct
snow dcm deploy \
  --target DEV \
  --from DCM_Platform/ \
  --connection your_connection_name \
  --role PLATFORM_DCM_ROLE
```

### Step 5: Create Streams (Post-Deploy)

```bash
snow sql \
  --connection your_connection_name \
  --role PLATFORM_DCM_ROLE \
  --filename DCM_Platform/scripts/create_streams.sql
```

### Step 6: GitHub Secrets

Add these secrets to your GitHub repository:

| Secret | Value |
|--------|-------|
| `SNOWFLAKE_ACCOUNT_NAME` | Your Snowflake account identifier |
| `SNOWFLAKE_DEV_USER` | Service account username |
| `SNOWFLAKE_DEV_PASSWORD` | Service account password |

---

## Key Commands

```bash
# Preview changes without deploying
snow dcm plan \
  --target DEV \
  --from DCM_Platform/ \
  --connection your_connection

# Deploy changes
snow dcm deploy \
  --target DEV \
  --from DCM_Platform/ \
  --connection your_connection

# Check what DCM is managing
snow sql -q "SHOW ENTITIES IN DCM PROJECT DCM_ADMIN.PROJECTS.PLATFORM_DEV;"

# Check deployment history
snow sql -q "SHOW DEPLOYMENTS IN DCM PROJECT DCM_ADMIN.PROJECTS.PLATFORM_DEV;"

# Monitor task execution
snow sql -q "SELECT * FROM TABLE(INFORMATION_SCHEMA.TASK_HISTORY()) ORDER BY SCHEDULED_TIME DESC LIMIT 10;"

# Verify streams
snow sql -q "SHOW STREAMS IN SCHEMA ANALYTICS_DEV.RAW;"
```

---

## Known Limitations

| Limitation | Impact | Workaround |
|------------|--------|------------|
| Streams not supported by DCM | Streams must be managed outside DCM | `scripts/create_streams.sql` run post-deploy |
| Columns can only be added at end of list | Cannot insert columns in middle of table | Design column order carefully upfront; use views for logical ordering |
| Cannot rename tables or columns | Renaming requires drop + recreate | Use blue-green deployment pattern for renames |
| DCM Projects in Public Preview | May have breaking changes | Pin CLI version in CI/CD; test before upgrading |

---

## References

- [Snowflake DCM Projects Documentation](https://docs.snowflake.com/en/user-guide/dcm-projects/dcm-projects-overview)
- [DCM Supported Object Types](https://docs.snowflake.com/en/user-guide/dcm-projects/dcm-projects-supported-entities)
- [Snowflake DevOps Guide](https://docs.snowflake.com/en/developer-guide/builders/devops)
- [Snowflake CLI Documentation](https://docs.snowflake.com/en/developer-guide/snowflake-cli/index)
- [Companion Repo: Terraform RBAC Automation](https://github.com/007ekho/Terraform-Snowflake-RBAC-Automation)
- [Companion Repo: Clinical Data Governance](https://github.com/007ekho/Multi-Tenant-Clinical-Data-Governance-Platform)

---

*Built by Success Ekhosuehi — Platform Engineer*
*Part of a production-grade Snowflake platform engineering portfolio*