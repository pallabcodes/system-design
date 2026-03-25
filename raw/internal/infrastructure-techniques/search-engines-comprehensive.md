# Search Engines Comprehensive Guide

> **Level**: Principal Architect / SDE-3
> **Scope**: Elasticsearch, Solr, Sharding, and Vector Search (RAG).

> [!TIP]
> **The 2026 Shift: Vector Search**. Traditional BM25/TF-IDF is keyword-based. For Semantic Search and RAG (Retrieval-Augmented Generation), you need **Vector Embeddings**. Elasticsearch 8.x and OpenSearch support `dense_vector` fields for kNN search.

## Overview

Search engines provide powerful full-text search capabilities, faceted search, aggregations, and real-time indexing for applications requiring advanced search functionality. This comprehensive guide covers Elasticsearch, Apache Solr, and enterprise patterns for building production-ready search systems.

## Table of Contents

1. [Core Concepts](#core-concepts)
2. [Elasticsearch Deep Dive](#elasticsearch-deep-dive)
3. [Apache Solr Deep Dive](#apache-solr-deep-dive)
4. [Indexing Strategies](#indexing-strategies)
5. [Query DSL](#query-dsl)
6. [Performance Optimization](#performance-optimization)
7. [Scaling and High Availability](#scaling-and-high-availability)
8. [Best Practices](#best-practices)
9. [Monitoring and Observability](#monitoring-and-observability)

## Core Concepts

### What is a Search Engine?

A search engine is a software system designed to search for information in a collection of documents, providing fast full-text search, relevance ranking, faceting, and aggregations.

### Key Features

- **Full-Text Search**: Search across document content
- **Relevance Ranking**: Score and rank results by relevance
- **Faceted Search**: Filter and categorize results
- **Aggregations**: Analyze and summarize data
- **Real-Time Indexing**: Near real-time document updates
- **Distributed**: Scale horizontally across clusters

### Use Cases

- **E-commerce**: Product search and filtering
- **Content Management**: Document and content search
- **Log Analytics**: Log aggregation and analysis (ELK stack)
- **Application Search**: User, order, transaction search
- **Analytics**: Business intelligence and reporting

## Elasticsearch Deep Dive

### Architecture

Elasticsearch is a distributed, RESTful search and analytics engine built on Apache Lucene.

### Core Concepts

- **Index**: Collection of documents (like a database)
- **Type**: Category of documents (deprecated in ES 7+)
- **Document**: JSON object stored in an index
- **Field**: Key-value pair in a document
- **Mapping**: Schema definition for fields
- **Shard**: Horizontal partition of an index
- **Replica**: Copy of a shard for high availability

### Installation

```bash
# Docker installation
docker run -d \
  --name=elasticsearch \
  -p 9200:9200 \
  -p 9300:9300 \
  -e "discovery.type=single-node" \
  -e "ES_JAVA_OPTS=-Xms512m -Xmx512m" \
  docker.elastic.co/elasticsearch/elasticsearch:8.11.0

# Verify installation
curl http://localhost:9200
```

### Cluster Setup

```yaml
# elasticsearch.yml
cluster.name: production-cluster
node.name: node-1
node.roles: [master, data, ingest]

network.host: 0.0.0.0
http.port: 9200

discovery.seed_hosts:
  - node-1:9300
  - node-2:9300
  - node-3:9300

cluster.initial_master_nodes:
  - node-1
  - node-2
  - node-3

xpack.security.enabled: true
xpack.security.transport.ssl.enabled: true
```

### Index Creation

```bash
# Create index with mapping
PUT /products
{
  "settings": {
    "number_of_shards": 3,
    "number_of_replicas": 1,
    "analysis": {
      "analyzer": {
        "custom_analyzer": {
          "type": "custom",
          "tokenizer": "standard",
          "filter": ["lowercase", "stop", "snowball"]
        }
      }
    }
  },
  "mappings": {
    "properties": {
      "name": {
        "type": "text",
        "analyzer": "custom_analyzer",
        "fields": {
          "keyword": {
            "type": "keyword"
          }
        }
      },
      "description": {
        "type": "text",
        "analyzer": "custom_analyzer"
      },
      "price": {
        "type": "float"
      },
      "category": {
        "type": "keyword"
      },
      "tags": {
        "type": "keyword"
      },
      "created_at": {
        "type": "date"
      },
      "location": {
        "type": "geo_point"
      }
    }
  }
}
```

### Document Indexing

```bash
# Index a document
POST /products/_doc
{
  "name": "Wireless Headphones",
  "description": "High-quality wireless headphones with noise cancellation",
  "price": 199.99,
  "category": "Electronics",
  "tags": ["wireless", "audio", "bluetooth"],
  "created_at": "2024-01-15T10:30:00Z",
  "location": {
    "lat": 40.7128,
    "lon": -74.0060
  }
}

# Bulk indexing
POST /products/_bulk
{"index":{}}
{"name":"Product 1","price":99.99,"category":"Electronics"}
{"index":{}}
{"name":"Product 2","price":149.99,"category":"Clothing"}
```

### Basic Search

```bash
# Simple search
GET /products/_search
{
  "query": {
    "match": {
      "name": "wireless headphones"
    }
  }
}

# Multi-match query
GET /products/_search
{
  "query": {
    "multi_match": {
      "query": "wireless",
      "fields": ["name^2", "description"]
    }
  }
}
```

### Advanced Queries

#### Boolean Query

```bash
GET /products/_search
{
  "query": {
    "bool": {
      "must": [
        {
          "match": {
            "name": "headphones"
          }
        }
      ],
      "filter": [
        {
          "range": {
            "price": {
              "gte": 100,
              "lte": 300
            }
          }
        },
        {
          "term": {
            "category": "Electronics"
          }
        }
      ],
      "must_not": [
        {
          "term": {
            "tags": "discontinued"
          }
        }
      ],
      "should": [
        {
          "match": {
            "description": "noise cancellation"
          }
        }
      ],
      "minimum_should_match": 1
    }
  }
}
```

#### Aggregations

```bash
GET /products/_search
{
  "size": 0,
  "aggs": {
    "categories": {
      "terms": {
        "field": "category",
        "size": 10
      }
    },
    "price_stats": {
      "stats": {
        "field": "price"
      }
    },
    "price_ranges": {
      "range": {
        "field": "price",
        "ranges": [
          {"to": 50},
          {"from": 50, "to": 100},
          {"from": 100, "to": 200},
          {"from": 200}
        ]
      }
    }
  }
}
```

#### Faceted Search

```bash
GET /products/_search
{
  "query": {
    "match_all": {}
  },
  "aggs": {
    "categories": {
      "terms": {
        "field": "category"
      }
    },
    "tags": {
      "terms": {
        "field": "tags"
      }
    },
    "price_histogram": {
      "histogram": {
        "field": "price",
        "interval": 50
      }
    }
  }
}
```

### Full-Text Search Features

#### Fuzzy Search

```bash
GET /products/_search
{
  "query": {
    "fuzzy": {
      "name": {
        "value": "headphons",
        "fuzziness": "AUTO"
      }
    }
  }
}
```

#### Phrase Matching

```bash
GET /products/_search
{
  "query": {
    "match_phrase": {
      "description": {
        "query": "noise cancellation",
        "slop": 2
      }
    }
  }
}
```

#### Highlighting

```bash
GET /products/_search
{
  "query": {
    "match": {
      "description": "wireless"
    }
  },
  "highlight": {
    "fields": {
      "description": {
        "type": "unified"
      }
    }
  }
}
```

### Geospatial Search

```bash
GET /products/_search
{
  "query": {
    "geo_distance": {
      "distance": "10km",
      "location": {
        "lat": 40.7128,
        "lon": -74.0060
      }
    }
  }
}
```

### Index Templates

```bash
PUT /_index_template/products_template
{
  "index_patterns": ["products-*"],
  "template": {
    "settings": {
      "number_of_shards": 3,
      "number_of_replicas": 1
    },
    "mappings": {
      "properties": {
        "name": {
          "type": "text"
        },
        "price": {
          "type": "float"
        }
      }
    }
  }
}
```

### Aliases

```bash
# Create alias
POST /_aliases
{
  "actions": [
    {
      "add": {
        "index": "products-2024-01",
        "alias": "products-current"
      }
    }
  ]
}

# Search using alias
GET /products-current/_search
{
  "query": {
    "match_all": {}
  }
}
```

## Apache Solr Deep Dive

### Architecture

Apache Solr is an open-source search platform built on Apache Lucene, providing RESTful APIs and advanced search features.

### Core Concepts

- **Collection**: Logical index (like Elasticsearch index)
- **Core**: Physical index with configuration
- **Document**: JSON/XML document stored in collection
- **Field**: Data field in a document
- **Schema**: Field definitions and types
- **Shard**: Horizontal partition
- **Replica**: Copy of a shard

### Installation

```bash
# Download Solr
wget https://archive.apache.org/dist/solr/solr/9.4.0/solr-9.4.0.tgz
tar xzf solr-9.4.0.tgz
cd solr-9.4.0

# Start Solr
bin/solr start

# Create collection
bin/solr create -c products -n basic_configs
```

### Schema Definition

```xml
<!-- managed-schema.xml -->
<schema name="products" version="1.6">
  <field name="id" type="string" indexed="true" stored="true" required="true"/>
  <field name="name" type="text_general" indexed="true" stored="true"/>
  <field name="description" type="text_general" indexed="true" stored="true"/>
  <field name="price" type="pfloat" indexed="true" stored="true"/>
  <field name="category" type="string" indexed="true" stored="true"/>
  <field name="tags" type="string" indexed="true" stored="true" multiValued="true"/>
  <field name="created_at" type="pdate" indexed="true" stored="true"/>
  
  <fieldType name="text_general" class="solr.TextField">
    <analyzer>
      <tokenizer class="solr.StandardTokenizerFactory"/>
      <filter class="solr.LowerCaseFilterFactory"/>
      <filter class="solr.StopFilterFactory" words="stopwords.txt"/>
      <filter class="solr.SnowballPorterFilterFactory"/>
    </analyzer>
  </fieldType>
  
  <uniqueKey>id</uniqueKey>
</schema>
```

### Document Indexing

```bash
# Index document (JSON)
curl -X POST http://localhost:8983/solr/products/update/json/docs \
  -H "Content-Type: application/json" \
  -d '{
    "id": "1",
    "name": "Wireless Headphones",
    "description": "High-quality wireless headphones",
    "price": 199.99,
    "category": "Electronics",
    "tags": ["wireless", "audio"]
  }'

# Commit changes
curl http://localhost:8983/solr/products/update?commit=true
```

### Basic Search

```bash
# Simple search
curl "http://localhost:8983/solr/products/select?q=wireless&wt=json"

# Field-specific search
curl "http://localhost:8983/solr/products/select?q=name:wireless&wt=json"

# Boolean query
curl "http://localhost:8983/solr/products/select?q=name:wireless+AND+category:Electronics&wt=json"
```

### Advanced Queries

#### Query Parser

```bash
# DisMax query parser
curl "http://localhost:8983/solr/products/select?q=wireless+headphones&defType=dismax&qf=name^2+description&wt=json"

# Extended DisMax (eDisMax)
curl "http://localhost:8983/solr/products/select?q=wireless+headphones&defType=edismax&qf=name^2+description&pf=name^3&wt=json"
```

#### Faceting

```bash
curl "http://localhost:8983/solr/products/select?q=*:*&facet=true&facet.field=category&facet.field=tags&wt=json"

# Facet with filters
curl "http://localhost:8983/solr/products/select?q=*:*&facet=true&facet.field=category&fq=price:[100+TO+300]&wt=json"
```

#### Filtering

```bash
# Range filter
curl "http://localhost:8983/solr/products/select?q=*:*&fq=price:[100+TO+300]&wt=json"

# Multiple filters
curl "http://localhost:8983/solr/products/select?q=*:*&fq=category:Electronics&fq=price:[100+TO+300]&wt=json"
```

### Solr Cloud (Distributed)

```bash
# Start Solr in cloud mode
bin/solr start -cloud -p 8983 -s example/cloud/node1/solr

# Create collection with sharding
bin/solr create_collection -c products -shards 3 -replicationFactor 2

# Add replica
bin/solr add -c products -shard shard1 -replicationFactor 2
```

## Indexing Strategies

### Batch Indexing

```python
# Python example with Elasticsearch
from elasticsearch import Elasticsearch
from elasticsearch.helpers import bulk

es = Elasticsearch(['localhost:9200'])

def generate_documents():
    for i in range(1000):
        yield {
            '_index': 'products',
            '_id': f'product-{i}',
            '_source': {
                'name': f'Product {i}',
                'price': 10.0 * i,
                'category': 'Electronics' if i % 2 == 0 else 'Clothing'
            }
        }

# Bulk index
bulk(es, generate_documents())
```

### Real-Time Indexing

```python
# Real-time indexing with refresh
from elasticsearch import Elasticsearch

es = Elasticsearch(['localhost:9200'])

# Index with immediate refresh
es.index(
    index='products',
    id='product-1',
    document={'name': 'New Product', 'price': 99.99},
    refresh='wait_for'  # Wait for refresh
)
```

### Update Strategies

```bash
# Partial update
POST /products/_update/product-1
{
  "doc": {
    "price": 149.99
  }
}

# Upsert (update or insert)
POST /products/_update/product-1
{
  "doc": {
    "name": "Updated Product",
    "price": 149.99
  },
  "doc_as_upsert": true
}
```

## Query DSL

### Elasticsearch Query DSL

```json
{
  "query": {
    "bool": {
      "must": [
        {"match": {"name": "wireless"}}
      ],
      "filter": [
        {"range": {"price": {"gte": 100, "lte": 300}}}
      ]
    }
  },
  "sort": [
    {"price": {"order": "asc"}},
    "_score"
  ],
  "from": 0,
  "size": 20,
  "highlight": {
    "fields": {
      "name": {},
      "description": {}
    }
  }
}
```

### Solr Query Syntax

```bash
# Standard query syntax
q=name:wireless AND price:[100 TO 300]

# DisMax query
q=wireless headphones&defType=dismax&qf=name^2 description

# Function query
q={!func}div(price,10)&sort=score desc
```

## Performance Optimization

### Index Optimization

```bash
# Force merge (optimize) index
POST /products/_forcemerge?max_num_segments=1

# Refresh interval
PUT /products/_settings
{
  "index": {
    "refresh_interval": "30s"
  }
}
```

### Query Optimization

```bash
# Use filter context instead of query context
GET /products/_search
{
  "query": {
    "bool": {
      "must": [
        {"match": {"name": "wireless"}}
      ],
      "filter": [
        {"term": {"category": "Electronics"}}
      ]
    }
  }
}

# Use _source filtering
GET /products/_search
{
  "_source": ["name", "price"],
  "query": {
    "match_all": {}
  }
}
```

### Caching

```bash
# Enable query cache
PUT /products/_settings
{
  "index": {
    "queries": {
      "cache": {
        "enabled": true
      }
    }
  }
}
```

## Scaling and High Availability

### Sharding Strategy

```bash
# Create index with custom sharding
PUT /products
{
  "settings": {
    "number_of_shards": 5,
    "number_of_replicas": 2
  }
}
```

### Cluster Management

```bash
# Check cluster health
GET /_cluster/health

# Get cluster settings
GET /_cluster/settings

# Update cluster settings
PUT /_cluster/settings
{
  "persistent": {
    "cluster.routing.allocation.enable": "all"
  }
}
```

### Index Lifecycle Management

```bash
# ILM policy
PUT /_ilm/policy/products-policy
{
  "policy": {
    "phases": {
      "hot": {
        "actions": {
          "rollover": {
            "max_size": "50GB",
            "max_age": "30d"
          }
        }
      },
      "warm": {
        "min_age": "7d",
        "actions": {
          "allocate": {
            "number_of_replicas": 1
          }
        }
      },
      "cold": {
        "min_age": "30d",
        "actions": {
          "allocate": {
            "number_of_replicas": 0
          }
        }
      },
      "delete": {
        "min_age": "90d",
        "actions": {
          "delete": {}
        }
      }
    }
  }
}
```

## Best Practices

### 1. Mapping Design

- Use appropriate field types
- Avoid dynamic mapping for production
- Use keyword fields for exact matches
- Use text fields for full-text search

### 2. Index Naming

- Use date-based indices for time-series data
- Use aliases for zero-downtime reindexing
- Implement index templates

### 3. Query Performance

- Use filter context for exact matches
- Limit result size
- Use _source filtering
- Enable query caching

### 4. Monitoring

- Monitor cluster health
- Track query performance
- Monitor index size
- Alert on errors

## Monitoring and Observability

### Cluster Health

```bash
# Cluster health
GET /_cluster/health?pretty

# Node stats
GET /_nodes/stats

# Index stats
GET /products/_stats
```

### Query Performance

```bash
# Profile query
GET /products/_search
{
  "profile": true,
  "query": {
    "match": {
      "name": "wireless"
    }
  }
}

# Explain query
GET /products/_explain/product-1
{
  "query": {
    "match": {
      "name": "wireless"
    }
  }
}
```

### Metrics

- **Cluster Metrics**: Health, nodes, shards
- **Index Metrics**: Size, document count, query performance
- **Query Metrics**: Latency, throughput, error rate
- **Resource Metrics**: CPU, memory, disk I/O

This comprehensive guide provides enterprise-grade search engine patterns and implementations for building production-ready search systems with Elasticsearch and Apache Solr, covering indexing, querying, performance optimization, and scaling strategies.

