# MariaDB — SQL Quick Reference

---

## 1. Connect via CLI

**Basic connection:**
```bash
mariadb -h <host> -P <port> -u <user> -p
```

**Connect and select a database directly:**
```bash
mariadb -h <host> -P <port> -u <user> -p <database>
```

**Connect via socket (localhost only):**
```bash
mariadb -u <user> -p
```

**Connect via SSH tunnel (tunnel must be open first):**
```bash
mariadb -h 127.0.0.1 -P 3307 -u <user> -p
```

**Run a single query without entering the shell:**
```bash
mariadb -h <host> -u <user> -p<password> -e "SHOW DATABASES;"
```

**Export a database dump:**
```bash
mariadump -h <host> -u <user> -p <database> > dump.sql
```

**Import a SQL file:**
```bash
mariadb -h <host> -u <user> -p <database> < dump.sql
```

---

## 2. User Management

**Create User:**
```sql
CREATE USER '<user>'@'%' IDENTIFIED BY '<password>';
```

**List users:**
```sql
SELECT User, Host FROM mysql.user;
```
**List all users:**
```sql
SELECT user, host, password_expired, is_role
FROM mysql.user
ORDER BY user;
```

**Check privileges for a specific user:**
```sql
SHOW GRANTS FOR '<user>'@'%';
```

**Full privilege matrix (all users):**
```sql
SELECT
    user, host,
    Select_priv, Insert_priv, Update_priv,
    Delete_priv, Create_priv, Drop_priv,
    Super_priv, Grant_priv
FROM mysql.user
ORDER BY user;
```

**Find users with SUPER privilege:**
```sql
SELECT user, host
FROM mysql.user
WHERE Super_priv = 'Y';
```

---

## 3. Databases & Tables

**List all databases:**
```sql
SHOW DATABASES;
```

**List all tables in current database:**
```sql
SHOW TABLES;
```

**List all tables across all databases:**
```sql
SELECT table_schema AS 'Database', table_name AS 'Table'
FROM information_schema.tables
WHERE table_type = 'BASE TABLE'
ORDER BY table_schema, table_name;
```

**Count tables per database:**
```sql
SELECT table_schema AS 'Database', COUNT(*) AS 'Total Tables'
FROM information_schema.tables
WHERE table_type = 'BASE TABLE'
GROUP BY table_schema
ORDER BY table_schema;
```

**Get table sizes (largest first):**
```sql
SELECT
    table_schema AS 'Database',
    table_name AS 'Table',
    ROUND((data_length + index_length) / 1024 / 1024, 2) AS 'Size (MB)',
    table_rows AS 'Approx Rows'
FROM information_schema.tables
WHERE table_type = 'BASE TABLE'
ORDER BY (data_length + index_length) DESC;
```

**Describe a table's structure:**
```sql
DESCRIBE <table>;
-- or
SHOW COLUMNS FROM <table>;
```

**Show indexes on a table:**
```sql
SHOW INDEX FROM <table>;
```

---

## 4. User Management

**Create a user:**
```sql
CREATE USER '<user>'@'%' IDENTIFIED BY '<password>';
```

**Grant read-only on all databases:**
```sql
GRANT SELECT ON *.* TO '<user>'@'%';
```

**Grant read-only on one database:**
```sql
GRANT SELECT ON <database>.* TO '<user>'@'%';
```

**Grant write on a specific table only:**
```sql
GRANT INSERT, UPDATE, DELETE ON <database>.<table> TO '<user>'@'%';
```

**Apply changes:**
```sql
FLUSH PRIVILEGES;
```

**Revoke a privilege:**
```sql
REVOKE INSERT, UPDATE, DELETE ON <database>.<table> FROM '<user>'@'%';
FLUSH PRIVILEGES;
```

**Change a user's password:**
```sql
ALTER USER '<user>'@'%' IDENTIFIED BY '<new_password>';
FLUSH PRIVILEGES;
```

**Delete a user:**
```sql
DROP USER '<user>'@'%';
FLUSH PRIVILEGES;
```

---

## 5. Performance

**Enable slow query log:**
```sql
SET GLOBAL slow_query_log = 'ON';
SET GLOBAL long_query_time = 5;
SET GLOBAL log_queries_not_using_indexes = 'ON';
```

**Show currently running queries:**
```sql
SHOW FULL PROCESSLIST;
```

**Kill a running query:**
```sql
KILL QUERY <process_id>;
```

**EXPLAIN a slow query:**
```sql
EXPLAIN FORMAT=JSON SELECT * FROM <table> WHERE <column> = '<value>';
```

**Check table status (engine, rows, size):**
```sql
SHOW TABLE STATUS FROM <database>;
```

---

*EXPLAIN red flags: `type: ALL` = full scan | `Using temporary` = temp table | `Using filesort` = no index sort | `DEPENDENT SUBQUERY` = N+1*

---

## 6. Backup & Restore

**Backup a database:**
```sql
mysqldump -u <user> -p <database> | gzip > <database>_$(date +%F).sql.gz
```

**Backup all databases:**
```sql
mysqldump -u <user> -p --all-databases | gzip > all_databases_$(date +%F).sql.gz
```

**Restore a database:**
```sql
gunzip < <file-name>.sql.gz | mysql -u <user> -p <database>
```

**SCP a backup file from remote server to your local machine:**
```bash
scp <remote-host>@<remote-ip>:/path/to/backup.sql.gz .
```

**SCP a backup file from local server to remote server**

```bash
scp /path/to/backup.sql.gz <remote-host>@<remote-ip>:/path/to/backup_directory/
```
---

### 6.1 Checking Live Database Size

Check for all the database that exists and their sizes.

```sql
SELECT 
    table_schema AS "Database", 
    ROUND(SUM(data_length + index_length) / 1024 / 1024, 2) AS "Size in MB" 
FROM 
    information_schema.TABLES 
WHERE 
    table_schema = DATABASE();
```

Check for a specific database and it's size

```sql
SELECT 
    table_schema AS "Database", 
    ROUND(SUM(data_length + index_length) / 1024 / 1024, 2) AS "Size in MB" 
FROM 
    information_schema.TABLES 
WHERE 
    table_schema = '<database-name>';
```

### 6.2 Restoring the zip file into database
Make sure you create a separate database and then restore it, because current data of existing database and data in zip file might create issues.
- If it is the same data and you are sure that it will not affect then only restore in the existing database.

```bash
zcat <database-backup-name>.sql.gz | mariadb -u <user> -p <database>


# you could use root as well for restoring
zcat <database-backup-name>.sql.gz | mariadb -u root -p <database>
```