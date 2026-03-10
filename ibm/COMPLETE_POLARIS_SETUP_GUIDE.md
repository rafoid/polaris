# Complete Apache Polaris Catalog with MinIO Setup Guide

## Overview
This guide documents the complete end-to-end setup of Apache Polaris Catalog with MinIO object storage, including building, deploying, and inserting data into tables.

## Table of Contents
1. [Prerequisites](#prerequisites)
2. [Step 1: Build Polaris Server](#step-1-build-polaris-server)
3. [Step 2: Start Services](#step-2-start-services)
4. [Step 3: Verify Deployment](#step-3-verify-deployment)
5. [Step 4: Create Namespace and Table](#step-4-create-namespace-and-table)
6. [Step 5: Insert Data Using Spark](#step-5-insert-data-using-spark)
7. [Configuration Reference](#configuration-reference)
8. [Troubleshooting](#troubleshooting)

## Prerequisites

- Docker 27+ (or Podman)
- Java 21+
- curl
- wget (for Spark download)
- 5GB free disk space

## Step 1: Build Polaris Server

Navigate to the Polaris repository and build the Docker image:

```bash
cd /work/repos/polaris_1.2

./gradlew \
  :polaris-server:assemble \
  :polaris-server:quarkusAppPartsBuild --rerun \
  -Dquarkus.container-image.build=true
```

**Verify the build:**
```bash
docker images | grep polaris
```

Expected output:
```
apache/polaris                    latest      <image-id>   <time>   608 MB
apache/polaris                    1.2.0-incubating   <image-id>   <time>   608 MB
```

## Step 2: Start Services

### Modify Docker Compose (if needed)

The docker-compose file at `getting-started/minio/docker-compose.yml` was modified to change the debug port from 5005 to 5006 to avoid conflicts.

### Start all services:

```bash
docker compose -f getting-started/minio/docker-compose.yml up -d
```

This starts:
- **MinIO** - Object storage (ports 9000, 9001)
- **Polaris** - Catalog server (ports 8181, 8182, 5006)
- **Setup containers** - Automatically create bucket and catalog

### Verify containers are running:

```bash
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
```

Expected output:
```
NAMES            STATUS                   PORTS
minio_minio_1    Up X seconds (healthy)   0.0.0.0:9000-9001->9000-9001/tcp
minio_polaris_1  Up X seconds (healthy)   0.0.0.0:5006->5005/tcp, 0.0.0.0:8181->8181/tcp
```

## Step 3: Verify Deployment

### Check Polaris is running:

```bash
# Get OAuth token
TOKEN=$(curl -s -X POST http://localhost:8181/api/catalog/v1/oauth/tokens -d 'grant_type=client_credentials&client_id=root&client_secret=s3cr3t&scope=PRINCIPAL_ROLE:ALL' | grep -o '"access_token":"[^"]*"' | cut -d'"' -f4)

# List catalogs
curl -s http://localhost:8181/api/management/v1/catalogs -H "Authorization: Bearer $TOKEN" | jq
```

Expected output shows the `quickstart_catalog` with MinIO configuration.

### Access MinIO Console:

Open browser to: http://localhost:9001
- Username: `minio_root`
- Password: `m1n1opwd`

## Step 4: Create Catalog, Namespace and Table

### Create catalog:
```bash
cd /work/repos/polaris_1.2
TOKEN=$(curl -s -X POST http://localhost:8181/api/catalog/v1/oauth/tokens -d 'grant_type=client_credentials&client_id=root&client_secret=s3cr3t&scope=PRINCIPAL_ROLE:ALL' | grep -o '"access_token":"[^"]*"' | cut -d'"' -f4)
# List catalogs
curl -s http://localhost:8181/api/management/v1/catalogs -H "Authorization: Bearer $TOKEN" | jq
# Create Catalog via REST API
curl -i -X POST http://localhost:8181/api/management/v1/catalogs -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' -d '{"catalog":{"type":"INTERNAL","name":"quickstart_catalog","properties":{"default-base-location":"s3://bucket123"},"storageConfigInfo":{"storageType":"S3","endpoint":"http://localhost:9000","endpointInternal":"http://minio:9000","pathStyleAccess":true,"allowedLocations":["s3://bucket123","s3://bucket123/*"]}}}'
# Grant CATALOG_MANAGE_CONTENT permission
curl -i -X PUT http://localhost:8181/api/management/v1/catalogs/quickstart_catalog/catalog-roles/catalog_admin/grants -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' -d '{"type":"catalog", "privilege":"CATALOG_MANAGE_CONTENT"}'
```

### Create a namespace:

```bash
TOKEN=$(curl -s -X POST http://localhost:8181/api/catalog/v1/oauth/tokens \
  -d 'grant_type=client_credentials&client_id=root&client_secret=s3cr3t&scope=PRINCIPAL_ROLE:ALL' \
  | grep -o '"access_token":"[^"]*"' | cut -d'"' -f4)

curl -s -X POST "http://localhost:8181/api/catalog/v1/quickstart_catalog/namespaces" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"namespace": ["test_ns"], "properties": {}}' | jq
```

### Create a table:

```bash
curl -s -X POST "http://localhost:8181/api/catalog/v1/quickstart_catalog/namespaces/test_ns/tables" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "test_table",
    "location": "s3://bucket123/test_ns/test_table",
    "schema": {
      "type": "struct",
      "schema-id": 0,
      "fields": [
        {"id": 1, "name": "id", "required": true, "type": "long"},
        {"id": 2, "name": "name", "required": false, "type": "string"},
        {"id": 3, "name": "created_at", "required": false, "type": "timestamp"}
      ]
    },
    "partition-spec": {"spec-id": 0, "fields": []},
    "write-order": {"order-id": 0, "fields": []},
    "properties": {}
  }' | jq
```

### Verify table creation:

```bash
curl -s "http://localhost:8181/api/catalog/v1/quickstart_catalog/namespaces/test_ns/tables" \
  -H "Authorization: Bearer $TOKEN" | python3 -m json.tool
```

## Step 5: Insert Data Using Spark

### Option A: Automated Script

Create and run the insertion script:

```bash
# Create SQL file with insert statements
cat > /tmp/insert_test_data.sql << 'EOF'
USE polaris;
SHOW NAMESPACES;
SHOW TABLES IN test_ns;

INSERT INTO test_ns.test_table VALUES
  (1, 'Alice Johnson', TIMESTAMP '2026-01-30 10:00:00'),
  (2, 'Bob Smith', TIMESTAMP '2026-01-30 11:30:00'),
  (3, 'Charlie Brown', TIMESTAMP '2026-01-30 12:45:00');

SELECT * FROM test_ns.test_table ORDER BY id;
DESCRIBE EXTENDED test_ns.test_table;
EOF

# Create and run the Spark script
cat > /tmp/run_insert.sh << 'SCRIPT'
#!/bin/bash
set -e

export SPARK_VERSION=spark-3.5.6
export SPARK_DISTRIBUTION=${SPARK_VERSION}-bin-hadoop3
export SPARK_HOME=~/${SPARK_DISTRIBUTION}
export SPARK_LOCAL_HOSTNAME=localhost

# Download Spark if not present
if [ ! -d "$SPARK_HOME" ]; then
    echo "Downloading Spark..."
    cd ~
    wget -q https://archive.apache.org/dist/spark/${SPARK_VERSION}/${SPARK_DISTRIBUTION}.tgz
    tar -xzf ${SPARK_DISTRIBUTION}.tgz
    rm ${SPARK_DISTRIBUTION}.tgz
fi

# Get OAuth token
TOKEN=$(curl -s -X POST http://localhost:8181/api/catalog/v1/oauth/tokens \
  -d 'grant_type=client_credentials&client_id=root&client_secret=s3cr3t&scope=PRINCIPAL_ROLE:ALL' \
  | grep -o '"access_token":"[^"]*"' | cut -d'"' -f4)

# Run Spark SQL
${SPARK_HOME}/bin/spark-sql \
  --packages org.apache.iceberg:iceberg-spark-runtime-3.5_2.12:1.9.0,org.apache.iceberg:iceberg-aws-bundle:1.9.0 \
  --conf spark.sql.extensions=org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions \
  --conf spark.sql.catalog.polaris=org.apache.iceberg.spark.SparkCatalog \
  --conf spark.sql.catalog.polaris.type=rest \
  --conf spark.sql.catalog.polaris.uri=http://localhost:8181/api/catalog \
  --conf spark.sql.catalog.polaris.token="${TOKEN}" \
  --conf spark.sql.catalog.polaris.warehouse=quickstart_catalog \
  --conf spark.sql.catalog.polaris.header.X-Iceberg-Access-Delegation=vended-credentials \
  --conf spark.sql.catalog.polaris.client.region=us-west-2 \
  --conf spark.hadoop.fs.s3a.endpoint=http://localhost:9000 \
  --conf spark.hadoop.fs.s3a.access.key=minio_root \
  --conf spark.hadoop.fs.s3a.secret.key=m1n1opwd \
  --conf spark.hadoop.fs.s3a.path.style.access=true \
  --conf spark.hadoop.fs.s3a.impl=org.apache.hadoop.fs.s3a.S3AFileSystem \
  --conf spark.sql.defaultCatalog=polaris \
  -f /tmp/insert_test_data.sql
SCRIPT

chmod +x /tmp/run_insert.sh
bash /tmp/run_insert.sh
```

### Option B: Interactive Spark SQL Shell

```bash
# Start Spark SQL shell
TOKEN=$(curl -s -X POST http://localhost:8181/api/catalog/v1/oauth/tokens -d 'grant_type=client_credentials&client_id=root&client_secret=s3cr3t&scope=PRINCIPAL_ROLE:ALL' | grep -o '"access_token":"[^"]*"' | cut -d'"' -f4)
~/spark-3.5.6-bin-hadoop3/bin/spark-sql \
  --packages org.apache.iceberg:iceberg-spark-runtime-3.5_2.12:1.9.0,org.apache.iceberg:iceberg-aws-bundle:1.9.0 \
  --conf spark.sql.extensions=org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions \
  --conf spark.sql.catalog.polaris=org.apache.iceberg.spark.SparkCatalog \
  --conf spark.sql.catalog.polaris.type=rest \
  --conf spark.sql.catalog.polaris.uri=http://9.30.117.69:8181/api/catalog \
  --conf spark.sql.catalog.polaris.token="${TOKEN}" \
  --conf spark.sql.catalog.polaris.warehouse=quickstart_catalog \
  --conf spark.sql.catalog.polaris.header.X-Iceberg-Access-Delegation=vended-credentials \
  --conf spark.sql.catalog.polaris.client.region=us-west-2 \
  --conf spark.hadoop.fs.s3a.endpoint=http://9.30.117.69:9000 \
  --conf spark.hadoop.fs.s3a.access.key=minio_root \
  --conf spark.hadoop.fs.s3a.secret.key=m1n1opwd \
  --conf spark.hadoop.fs.s3a.path.style.access=true \
  --conf spark.hadoop.fs.s3a.impl=org.apache.hadoop.fs.s3a.S3AFileSystem \
  --conf spark.sql.defaultCatalog=polaris
```

Then in the Spark SQL shell:
```sql
USE polaris;
INSERT INTO test_ns.test_table VALUES
  (1, 'Alice Johnson', TIMESTAMP '2026-01-30 10:00:00'),
  (2, 'Bob Smith', TIMESTAMP '2026-01-30 11:30:00'),
  (3, 'Charlie Brown', TIMESTAMP '2026-01-30 12:45:00');
SELECT * FROM test_ns.test_table ORDER BY id;
```

### Verify Data in MinIO

1. Open MinIO Console: http://localhost:9001
2. Navigate to bucket `bucket123`
3. Browse to `test_ns/test_table/data/`
4. You should see Parquet data files

## Configuration Reference

### Polaris Configuration

| Setting | Value |
|---------|-------|
| Realm | POLARIS |
| Client ID | root |
| Client Secret | s3cr3t |
| Catalog Name | quickstart_catalog |
| Storage Location | s3://bucket123 |
| API Port | 8181 |
| Management Port | 8182 |
| Debug Port | 5006 (host) → 5005 (container) |

### MinIO Configuration

| Setting | Value |
|---------|-------|
| Root User | minio_root |
| Root Password | m1n1opwd |
| Bucket Name | bucket123 |
| API Port | 9000 |
| Console Port | 9001 |
| API Endpoint (external) | http://localhost:9000 |
| API Endpoint (internal) | http://minio:9000 |

### Spark Configuration for Polaris

Key Spark configurations:
```properties
spark.sql.catalog.polaris=org.apache.iceberg.spark.SparkCatalog
spark.sql.catalog.polaris.type=rest
spark.sql.catalog.polaris.uri=http://localhost:8181/api/catalog
spark.sql.catalog.polaris.warehouse=quickstart_catalog
spark.sql.catalog.polaris.header.X-Iceberg-Access-Delegation=vended-credentials
spark.hadoop.fs.s3a.endpoint=http://localhost:9000
spark.hadoop.fs.s3a.path.style.access=true
```

## Management Commands

### Start Services
```bash
docker compose -f getting-started/minio/docker-compose.yml up -d
```

### Stop Services
```bash
docker compose -f getting-started/minio/docker-compose.yml down
```

### View Logs
```bash
# Polaris logs
docker logs minio_polaris_1 -f

# MinIO logs
docker logs minio_minio_1 -f
```

### Restart Services
```bash
docker compose -f getting-started/minio/docker-compose.yml restart
```

### Clean Up Everything
```bash
docker compose -f getting-started/minio/docker-compose.yml down -v
rm -rf ~/spark-3.5.6-bin-hadoop3
```

## Troubleshooting

### Port Conflicts

If ports are already in use:
1. Check what's using the port: `lsof -i :8181`
2. Stop the conflicting service or modify `docker-compose.yml`

### Spark Download Issues

If Spark download fails:
```bash
# Manual download
cd ~
wget https://archive.apache.org/dist/spark/spark-3.5.6/spark-3.5.6-bin-hadoop3.tgz
tar -xzf spark-3.5.6-bin-hadoop3.tgz
```

### Authentication Errors

Verify credentials:
```bash
curl -X POST http://localhost:8181/api/catalog/v1/oauth/tokens \
  -d 'grant_type=client_credentials&client_id=root&client_secret=s3cr3t&scope=PRINCIPAL_ROLE:ALL'
```

### Data Not Appearing in MinIO

1. Check table location:
```bash
TOKEN=$(curl -s -X POST http://localhost:8181/api/catalog/v1/oauth/tokens \
  -d 'grant_type=client_credentials&client_id=root&client_secret=s3cr3t&scope=PRINCIPAL_ROLE:ALL' \
  | grep -o '"access_token":"[^"]*"' | cut -d'"' -f4)

curl -s "http://localhost:8181/api/catalog/v1/quickstart_catalog/namespaces/test_ns/tables/test_table" \
  -H "Authorization: Bearer $TOKEN" | python3 -m json.tool | grep location
```

2. Verify MinIO bucket exists:
```bash
docker exec minio_minio_1 mc ls pol/
```

### Spark Connection Issues

Ensure:
- Polaris is running and healthy
- OAuth token is valid (not expired)
- MinIO is accessible
- Network connectivity between Spark and services

## Summary

You have successfully:
- ✅ Built Polaris server Docker image
- ✅ Deployed Polaris with MinIO storage
- ✅ Created a catalog, namespace, and table
- ✅ Inserted data using Spark SQL
- ✅ Verified data is stored in MinIO

Your Polaris Catalog is now fully operational with data!

## Next Steps

1. **Explore More Features:**
   - Create views
   - Set up table partitioning
   - Configure time travel queries
   - Implement row-level security

2. **Production Readiness:**
   - Configure PostgreSQL for persistent metadata
   - Enable TLS/SSL
   - Set up monitoring with Prometheus/Grafana
   - Implement backup strategies

3. **Integration:**
   - Connect other query engines (Trino, Dremio, Flink)
   - Set up CI/CD pipelines
   - Implement data governance policies

## Resources

- [Apache Polaris Documentation](https://polaris.apache.org)
- [Apache Iceberg Documentation](https://iceberg.apache.org)
- [MinIO Documentation](https://min.io/docs/)
- [Apache Spark Documentation](https://spark.apache.org/docs/latest/)