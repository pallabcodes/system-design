# System Design Knowledge System

This repository is a structured, pattern-based knowledge system for system design and database management. It is optimized for retrieval and agent usage.

## 🏗️ Repository Structure

- `patterns/`: Primary knowledge base. Each file represents a specific system design pattern.
- `raw/internal/`: Secondary knowledge base. Contains original notes, blogs, and unstructured content.
- `database/`: Comprehensive database patterns, techniques, and enterprise-level solutions (SQL & NoSQL).
- `scripts/`: Tools for managing and querying the knowledge base.
- `AGENTS.md`: Strict rules for agent usage.

## 🗄️ Database Management Focus

This section contains patterns for major tech companies like Google, Atlassian, PayPal, Stripe, Netflix, Uber, etc.

### SQL Databases
- **MySQL**: Schema design, sharding, multi-tenancy, event sourcing.
- **PostgreSQL**: Industry-specific schemas, replication, security.
- **SQL Server**: E-commerce schemas, performance tuning.

### NoSQL Databases
- **MongoDB, DynamoDB, Cassandra, Redis**: Schema design, performance, industry niches.

## 🚀 Enterprise Patterns
- **Sharding & Partitioning**
- **Multi-Tenancy**
- **Event Sourcing & CQRS**
- **Distributed Transactions**
- **High Availability**

## 🔧 Getting Started
1. Navigate to the specific pattern you want to learn.
2. Review the README files for explanations.
3. Study the implementations and examples.

## QMD Setup
```bash
# Initialize QMD
qmd init

# Add pattern collection
qmd collection add ./patterns --name system-design

# Add raw docs collection
qmd collection add ./raw/internal --name raw-docs
```
