# System Design Knowledge System

This repository is a structured, pattern-based knowledge system for system design. It is optimized for retrieval and agent usage.

## Structure

- `patterns/`: Primary knowledge base. Each file represents a specific system design pattern.
  - `scalability/`
  - `distributed/`
  - `performance/`
  - `databases/`
  - `caching/`
  - `reliability/`
- `raw/internal/`: Secondary knowledge base. Contains original notes, blogs, and unstructured content.
- `scripts/`: Tools for managing and querying the knowledge base.
- `AGENTS.md`: Strict rules for agent usage.

## QMD Setup

To initialize and use the retrieval system:

```bash
# Initialize QMD
qmd init

# Add pattern collection
qmd collection add ./patterns --name system-design

# Add raw docs collection
qmd collection add ./raw --name raw-docs
```

## Pattern Unit Format

Each pattern follows a strict template defined in `patterns/TEMPLATE.md`.

## Usage for Agents

See `AGENTS.md` for strict usage rules. Agents MUST use QMD to retrieve patterns before answering.
