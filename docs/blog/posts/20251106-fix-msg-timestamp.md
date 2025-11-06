---
authors:
  - ionling
categories:
  - Backend
  - Database
date: 2025-11-06
---

# Debugging That Weird PostgreSQL Timestamp Issue

Ever run into this situation? You're inserting multiple records in a transaction,
expecting them to have slightly different timestamps, but when you check the database

- surprise! - they all have the exact same `created_at` timestamp.

I spent hours debugging this issue in production before realizing it wasn't a bug -
it was expected PostgreSQL behavior.

## What You're Probably Seeing

You have code that looks something like this:

```go
// Inside a transaction
err := db.RunInTx(ctx, func(tx *sql.Tx) error {
    // Insert first record
    _, err := tx.Exec("INSERT INTO users (name) VALUES ($1) RETURNING created_at", "Alice")

    // Some processing happens here...

    // Insert second record
    _, err = tx.Exec("INSERT INTO users (name) VALUES ($1) RETURNING created_at", "Bob")

    return nil
})

// Later in your code...
if user1.CreatedAt.Equal(user2.CreatedAt) {
    // This should be false, but it's true!
    log.Println("Timestamps are identical - WTF?")
}
```

## Understanding PostgreSQL Timestamp Functions

PostgreSQL provides several timestamp functions, each with different behavior:

<!-- markdownlint-disable MD013 -->

| Function                  | When Evaluated    | Changes Within Transaction? | Use Case                        |
| ------------------------- | ----------------- | --------------------------- | ------------------------------- |
| `now()`                   | Transaction start | ❌ No                       | Logical transaction consistency |
| `transaction_timestamp()` | Transaction start | ❌ No                       | Same as `now()`                 |
| `statement_timestamp()`   | Statement start   | ❌ No                       | Per-statement uniqueness        |
| `clock_timestamp()`       | Every call        | ✅ Yes                      | Real-time precision             |

<!-- markdownlint-enable -->

**Here's the deal**: By default, most database schemas use `now()` or `transaction_timestamp()`,
which return the same timestamp for all operations within a single transaction.

## The Fix: Switch to `statement_timestamp()`

The cleanest solution is to change your database schema to use `statement_timestamp()`.
This gives you a unique timestamp for each SQL statement
while preserving all the benefits of transaction isolation.

### Database Migration

```sql
-- Replace 'your_table_name' with your actual table name

-- Drop existing trigger if it exists
DROP TRIGGER IF EXISTS updated_at ON your_table_name;

-- Update default values to use statement_timestamp()
ALTER TABLE your_table_name
ALTER COLUMN created_at SET DEFAULT statement_timestamp();

ALTER TABLE your_table_name
ALTER COLUMN updated_at SET DEFAULT statement_timestamp();

-- Recreate the trigger for automatic updated_at updates
CREATE TRIGGER updated_at BEFORE
UPDATE ON your_table_name FOR EACH ROW EXECUTE FUNCTION updated_at_statement();
```

### Before and After Comparison

**Before (using `now()`)**:

```go
// Both records get timestamp: 2024-01-15 10:30:00.123
record1.CreatedAt.Equal(record2.CreatedAt) // true
```

**After (using `statement_timestamp()`)**:

```go
// record1 gets: 2024-01-15 10:30:00.123
// record2 gets: 2024-01-15 10:30:00.456
record1.CreatedAt.Equal(record2.CreatedAt) // false
```

## Why `statement_timestamp()` is the Best Choice

- ✅ **Per-statement uniqueness**: Each INSERT/UPDATE gets its own timestamp
- ✅ **Transaction safety**: Maintains ACID properties
- ✅ **Logical ordering**: Records maintain chronological order
- ✅ **Performance**: More efficient than `clock_timestamp()`
- ✅ **Predictable**: Consistent behavior across different database setups

## Alternative Approaches

### 1. Application-Generated Timestamps

```go
record1.CreatedAt = time.Now()
record2.CreatedAt = time.Now().Add(time.Microsecond * 100)
```

- _Pros_: Full control over timestamps
- _Cons_: Requires code changes

### 2. Use `clock_timestamp()`

```sql
ALTER TABLE your_table_name
ALTER COLUMN created_at SET DEFAULT clock_timestamp();
```

- _Pros_: Real-time timestamps
- _Cons_: Performance overhead, may be too precise

## Testing Your Fix

1. **Verify the migration**: Check that your table columns now use `statement_timestamp()`
2. **Test in isolation**: Insert a few records and verify different timestamps
3. **Test with transactions**: Run your existing transaction logic
4. **Check logs**: Ensure debug logs show different timestamps
5. **Query validation**: Confirm chronological ordering in SELECT queries

## Common Gotchas

- ⚠️ **Triggers**: Remember to update any automatic timestamp triggers
- ⚠️ **Default values**: Check other tables that might have similar issues
- ⚠️ **Time zones**: Ensure your application handles timezone consistently
- ⚠️ **Precision**: `statement_timestamp()` still has microsecond precision limits

This fix ensures that records inserted within the same transaction
maintain proper chronological ordering while preserving all the benefits of database transactions.
