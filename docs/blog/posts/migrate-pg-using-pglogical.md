---
authors:
  - ionling
categories:
  - DevOps
  - Database
date: 2024-01-15
---

# Migrate PostgreSQL Databases Using pglogical

## Introduction

To reduce the latency of database queries,
we have decided to migrate our Postgres database from one zone to a zone closer to our application.

## TLDR

To minimize application downtime, we have chosen continuous migration using [pglogical].

### Change config

We need to modify the database configuration, enable the pglogical extension,
and restart the instance.
If you have multiple databases to migrate,
please check [worker registration failed](#error-worker-registration-failed)
for configuring `max_worker_processes` correctly.

```toml
# Ref https://github.com/2ndQuadrant/pglogical#quick-setup

wal_level = 'logical'
max_worker_processes = 16   # one per database needed on provider node
                            # one per node needed on subscriber node
max_replication_slots = 16  # one per node needed on provider node
max_wal_senders = 16        # one per node needed on provider node
shared_preload_libraries = 'pglogical'

track_commit_timestamp = on # needed for last/first update wins conflict resolution
                            # property available in PostgreSQL 9.5+
```

You can use `SHOW` to check the config parameter:

```sql
SHOW wal_level;
SHOW shared_preload_libraries;
```

### DDL

To start with pglogical, it's crucial to ensure that the database structures
of both the provider and subscriber are identical.
We employ our [goose] based migration for this purpose.
However when creating a subscription using `pglogical.create_subscription()`,
you can set the `synchronize_structure` parameter to `true`,
but it requres that the owner of these structures also exists in the subscriber.

### Create subscription

On the provider node:

```sql
-- Create a user for logical replication
CREATE ROLE logicalrep WITH LOGIN;
ALTER USER logicalrep WITH PASSWORD 'your_pass';


-- Here we use pglogical extentsion
create extension pglogical;


-- The dsn can be blank
SELECT pglogical.create_node(
    node_name := 'provider1',
    dsn := ''
);

-- Add all tables in public schema to the default replication set
SELECT pglogical.replication_set_add_all_tables('default', ARRAY['public']);

-- Grant privileges to the logicalrep user
GRANT USAGE ON schema public TO logicalrep;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO logicalrep;
GRANT USAGE ON schema pglogical TO logicalrep;
GRANT SELECT ON ALL TABLES IN SCHEMA pglogical TO logicalrep;
```

On the subscriber node:

Here we sync the `order` database.

```sql
CREATE EXTENSION pglogical;
SELECT pglogical.create_node(
    node_name := 'sub',
    dsn := 'dbname=order'
);

-- Create subscription
SELECT pglogical.create_subscription(
    subscription_name := 'sub_order',
    provider_dsn := 'host=your_host port=5432 dbname=order user=logicalrep password=your_pass'
);

-- Check it
--
-- Expected status is `replicating`.
-- If not, check the database log for details (provider or subscriber node).
select * from pglogical.show_subscription_status();
```

### Sync sequences

One common mistake people make is forgetting the last values of sequences,
which can lead to duplicated key errors.

We write a script to do this.
The new last value will be 1.1 times the origin, factoring in subscription latency.
The primary SQL statement is:

```sql
-- Get last values
SELECT * FROM pg_sequences;

-- Apply them to subscriber
ALTER SEQUENCE public.videos_id_seq RESTART new_value;

-- To check the last value of altered sequences, you can use the following SQL.
-- Note that `SELECT * FROM pg_sequences` will show NULL last value after you alter it.
-- Refer to https://gist.github.com/lbbedendo/449ff46d3baa7838b99ec513c2de92a7
SELECT last_value FROM public.videos_id_seq;
```

### Check rows

We've crafted a script to verify the equality of
both the row count and a randomly selected subset of rows.
See: <https://gist.github.com/ionling/10f50bf3d77040fa8bb4f6695c23befe>

### Drop subsription

Once we confirm that the source and target databases are in a consistent state,
we can proceed to drop the subscription.

```sql
SELECT * FROM pglogical.drop_subscription('sub_order');
```

## Solutions

Here, we will explore several solutions for the migration process.

### Dump and restore

Dumping the old database and restoring it to the new database is a viable approach.
However, it comes with the drawback of causing a significant downtime, which is undesirable.
During this downtime, tasks such as database restoration, data verification,
and service restarts are necessary, consuming a considerable amount of time.

### Streaming replication

PostgreSQL offers native support for streaming replication,
facilitating continuous synchronization of data from a source database to a new one.
This approach significantly reduces service downtime.
By configuring replication in advance, the migration process only requires restarting services,
making it more efficient and minimizing downtime.

### Multi-master

The best solution is to combine the old and new databases in a multi-master cluster.
This allows us to smoothly migrate any service
that relies on the old database to the new without any downtime.

One implementation for achieving this is through the [spock] extension.
However, the performance and potential issues of this extension might be a concern.
For more insights, you can refer to the blog post:
[How to achieve multi-master replication in PostgreSQL with Spock](https://www.pgedge.com/blog/achieve-multiactive-data-replication-in-postgresql-with-spock)

### Summary

To strike a balance between complexity and functionality,
we ultimately opted for the streaming replication solution.

AWS has a blog on database upgrading that is also useful for migrating:

1. <https://aws.amazon.com/cn/blogs/database/part-1-upgrade-your-amazon-rds-for-postgresql-database-comparing-upgrade-approaches/>
2. <https://aws.amazon.com/cn/blogs/database/part-2-upgrade-your-amazon-rds-for-postgresql-database-using-the-pglogical-extension/>

## Notes

### Could not open relation with OID

When debugging the subscription, I mistakenly dropped the [pglogical] extension,
deleted the pglogical schema, and subsequently recreated it.
As a consequence, I encounter a error when running certain pg commands:

```text
Could not open relation with OID
```

To resolve it, just reconnect the db.

See <https://github.com/2ndQuadrant/pglogical/issues/347>

### PostgreSQL priveledges

Some priveledges are not intuitive, like this:

```sql
GRANT ALL ON DATABASE mydb TO admin;
```

grants privileges on the database itself, not things within the database.
admin can now drop the database, still without being able to create tables in schema public.[^1]

### ERROR: worker registration failed

When creating a subscription, we encountered the following error:

```log
ERROR: worker registration failed, you might want to increase max_worker_processes setting
```

According to the [pglogical] README:

> one process per node is needed on the subscriber node.

After ensuring that we do not exceed the limit,
we started searching for related documents and encountered two conflicting pieces of information.

One, from [EnterpriseDB](https://www.enterprisedb.com/docs/pgd/3.7/pglogical/configuration/),
states:

> One per database + two per subscription on the subscriber (downstream).

The other, from [GitHub Issue #7](https://github.com/2ndQuadrant/pglogical/issues/7),
mentions:

> One worker needed for the main maintenance process,
> one per subscription, one per replicated database,
> and during startup, it can need one per any connectable database on top of that.

If we have two databases with one subscription for each database:

- According to quote one, we will need `2*1 + 2*2 = 6` processes.
- According to quote two, we will need `2*2 = 4` processes.

Which one is correct? I don't know.

### Other tools

- <https://github.com/shayonj/pg_easy_replicate>
- <https://bucardo.org/>

## References

- [PostgreSQL bi-directional replication using pglogical | AWS Database Blog](https://aws.amazon.com/cn/blogs/database/postgresql-bi-directional-replication-using-pglogical/)
- [pglogical - Database Migration Guide](https://docs.aws.amazon.com/dms/latest/sbs/chap-manageddatabases.postgresql-rds-postgresql-full-load-pglogical.html)
- [Zero downtime Postgres migration, done right](https://engineering.theblueground.com/zero-downtime-postgres-migration-done-right/)
- [Container Security: Tips for Securing PostgreSQL Instances in Docker | by Pan...](https://pankajconnect.medium.com/container-security-tips-for-securing-postgresql-instances-in-docker-9de5d2a932fb)
- [如何使用逻辑流复制发布和订阅功能\_云数据库 RDS(RDS)-阿里云帮助中心](https://help.aliyun.com/zh/rds/apsaradb-rds-for-postgresql/use-the-pglogical-extension-for-logical-streaming-replication)

[^1]: <https://stackoverflow.com/a/74111630/7134763>

[goose]: https://github.com/pressly/goose
[pglogical]: https://github.com/2ndQuadrant/pglogical
[spock]: https://github.com/pgEdge/spock
