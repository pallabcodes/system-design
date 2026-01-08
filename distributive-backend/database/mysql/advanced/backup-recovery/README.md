# SQL Server Backup & Recovery

## Overview

A robust backup and recovery strategy is the most critical component of a disaster recovery plan. It ensures that data can be recovered in the event of hardware failure, data corruption, or accidental deletions.

## Recovery Models

The recovery model controls how the transaction log is managed and what kind of restore operations are possible.

1.  **Simple Recovery Model**
    - **Description**: No log backups. Transaction log is automatically truncated.
    - **Pros**: Low administrative effort. Small log files.
    - **Cons**: Can only recover to the end of the last full/differential backup. No point-in-time recovery.
    - **Use Case**: Dev/Test environments, Read-only data.

2.  **Full Recovery Model**
    - **Description**: Requires transaction log backups. Log is not truncated until backed up.
    - **Pros**: Point-in-time recovery. Supports individual page restores.
    - **Cons**: Requires regular log backups to prevent log from filling disk.
    - **Use Case**: Production critical systems.

3.  **Bulk-Logged Recovery Model**
    - **Description**: Similar to Full, but minimally logs bulk operations (BULK INSERT, CREATE INDEX).
    - **Pros**: Improved performance for bulk loads.
    - **Cons**: No point-in-time recovery for the period of the bulk operation.

## Backup Types

- **Full Backup**: Contains all data in the database.
- **Differential Backup**: Contains data changed since the last Full backup. Faster to create.
- **Transaction Log Backup**: Captures the transaction log. Essential for point-in-time recovery (Full Model).
- **Copy-Only Backup**: A special full backup that does not break the differential backup chain.

## Restore Strategy

- **RTO (Recovery Time Objective)**: How long can you afford to be down?
- **RPO (Recovery Point Objective)**: How much data can you afford to lose?

**Typical Strategy**:
- Full Backup Weekly (Sunday)
- Differential Backup Daily (Mon-Sat)
- Log Backup Every 15 Minutes
