# Testing & Verification Guide

This guide helps you verify that log streaming is working correctly.

**Note:** The installer supports both systemd service and manual deployments. The verification steps are the same for both, but manual deployments will have environment variables set in `~/.bashrc`.

---

## Quick Health Check

Run these commands in order:

```bash
# 1. Check Vector service status
sudo systemctl status vector

# 2. Verify Vector is watching your log file
sudo journalctl -u vector -n 50 | grep "Found new file to watch"

# 3. Check if Vector has the file open
sudo lsof -p $(pgrep vector) | grep curio

# 4. Watch logs being processed in real-time
sudo journalctl -u vector -f
```

**Expected output:**
- Vector status: `Active: active (running)`
- Found message with your curio.log path
- lsof shows vector has curio.log open
- Journalctl shows no errors

---

## Detailed Verification

### 1. Verify Vector Configuration

```bash
# Validate the config
sudo vector validate --config /etc/vector/vector.yaml

# Check config contents
cat /etc/vector/vector.yaml
```

**Look for:**
- Your `client_id` set correctly
- Your log file path in `include:`
- No syntax errors in validation

### 2. Check File Permissions

```bash
# Verify log directory permissions
ls -ld /var/log/curio/
ls -l /var/log/curio/curio.log

# Directory should be 755 (readable by all)
# File should be 644 (readable by all)

# If permissions are wrong:
sudo chmod 755 /var/log/curio/
sudo chmod 644 /var/log/curio/curio.log
sudo systemctl restart vector
```

### 3. Verify Curio Logging Configuration

**For systemd deployments:**
```bash
# Check service environment variables
sudo systemctl show curio -p Environment
# Should show GOLOG_FILE and GOLOG_LOG_FMT
```

**For manual deployments:**
```bash
# Check bashrc has the environment variables
grep GOLOG ~/.bashrc
# Should show GOLOG_OUTPUT, GOLOG_FILE, and GOLOG_LOG_FMT
```

**Verify log format:**
```bash
# Check that curio.log is JSON formatted
head -1 /var/log/curio/curio.log

# Should see JSON like:
# {"level":"info","ts":"2025-10-23T...","logger":"...","msg":"..."}
```

**If not JSON:**
- For systemd: Check service file has `Environment=GOLOG_LOG_FMT="json"`
- For manual: Check `~/.bashrc` has `export GOLOG_LOG_FMT="json"`
- Restart Curio

### 4. Test Log Generation

```bash
# Add a test line to curio.log
echo '{"level":"info","ts":"'$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)'","msg":"TEST_LOG_STREAMING","test":true}' | sudo tee -a /var/log/curio/curio.log

# Wait 2 seconds (for batching)
sleep 2

# Check Better Stack dashboard for "TEST_LOG_STREAMING"
```

---

## Better Stack Dashboard Checks

### 1. Access Dashboard

Go to: https://s1560290.eu-nbg-2.betterstackdata.com

### 2. Filter by Client ID

In the search/filter box:
```
client_id:"your-client-id"
```

Replace with your actual client ID.

### 3. Check Visible Fields

Each log should have:
- `client_id` - Your client ID
- `platform` - "Curio PDP"
- `dt` - Timestamp
- `level` - Log level (info, warn, error)
- `msg` - Log message
- Other Curio-specific fields

### 4. Verify Recent Logs

Set time range to "Last 5 minutes" and verify you see recent logs.

---

## Common Issues & Fixes

### Issue: Vector not starting

**Symptoms:**
```bash
sudo systemctl status vector
# Shows: failed or inactive
```

**Fix:**
```bash
# Check for config errors
sudo vector validate --config /etc/vector/vector.yaml

# View error details
sudo journalctl -u vector -n 50

# Common fixes:
# - Fix YAML syntax errors
# - Verify file paths exist
# - Check permissions
```

### Issue: No logs in Better Stack

**Symptoms:**
- Vector running fine
- But no logs appearing in dashboard

**Debug steps:**

1. **Check if Vector is reading the file:**
   ```bash
   sudo lsof -p $(pgrep vector) | grep curio
   ```
   If empty, Vector can't access the file.

2. **Verify file permissions:**
   ```bash
   ls -ld /var/log/curio/
   ls -l /var/log/curio/curio.log
   ```
   If permissions are wrong:
   ```bash
   sudo chmod 755 /var/log/curio/
   sudo chmod 644 /var/log/curio/curio.log
   sudo systemctl restart vector
   ```

3. **Check for network errors:**
   ```bash
   sudo journalctl -u vector | grep -i "error\|fail"
   ```

4. **Verify batching is working:**
   Wait at least 5 seconds after new logs are written. Vector batches logs before sending.

### Issue: "Permission denied" errors

**Symptoms:**
```
Permission denied: /var/log/curio/curio.log
```

**Fix:**
```bash
# Check file and directory permissions
ls -ld /var/log/curio/
ls -l /var/log/curio/curio.log

# Directory should be readable (755 or similar)
# File should be readable (644 or similar)

# If permissions are wrong, Curio should recreate with correct perms on restart
# Or manually fix:
sudo chmod 755 /var/log/curio/
sudo chmod 644 /var/log/curio/curio.log

# Restart Vector
sudo systemctl restart vector
```

### Issue: Old logs not appearing

**Expected behavior:**
- Vector config has `read_from: "end"`
- This means Vector only reads NEW logs (written after it starts)
- Old logs before Vector started won't be sent

**To send old logs (one-time):**
```bash
# Stop Vector
sudo systemctl stop vector

# Edit config to read from beginning
sudo sed -i 's/read_from: "end"/read_from: "beginning"/' /etc/vector/vector.yaml

# Delete checkpoint
sudo rm -rf /var/lib/vector/*

# Restart Vector
sudo systemctl start vector

# Wait for logs to upload, then change back to "end"
sudo sed -i 's/read_from: "beginning"/read_from: "end"/' /etc/vector/vector.yaml
sudo systemctl restart vector
```

---

## Performance Monitoring

### Check Vector Resource Usage

```bash
# CPU and Memory
ps aux | grep vector

# Detailed stats
systemctl status vector
```

**Expected:**
- Memory: ~50-150MB
- CPU: <1% (idle), 1-5% (active logging)

### Check Disk I/O

```bash
# Watch Vector checkpoint files
watch -n 1 ls -lh /var/lib/vector/*/checkpoints.json
```

Checkpoint file size should update as logs are processed.

---

## Advanced Debugging

### Enable Debug Logging

```bash
# Stop Vector
sudo systemctl stop vector

# Run Vector in foreground with debug logging
sudo vector --config /etc/vector/vector.yaml --verbose

# Press Ctrl+C to stop
# Then restart normally:
sudo systemctl start vector
```

### Test Vector Config Locally

```bash
# Create a test log file
echo '{"msg":"test"}' > /tmp/test.log

# Create a test config
cat > /tmp/vector-test.yaml <<EOF
sources:
  test:
    type: "file"
    include: ["/tmp/test.log"]

sinks:
  console:
    type: "console"
    inputs: ["test"]
    encoding:
      codec: "json"
EOF

# Run Vector with test config
vector --config /tmp/vector-test.yaml

# Should see the log output to console
```

### Check Network Connectivity

```bash
# Test connection to Better Stack
curl -v -X POST https://s1560290.eu-nbg-2.betterstackdata.com/ \
  -H "Authorization: Bearer LzoJaWSF4bbA4ic1JEeQ4TK7" \
  -H "Content-Type: application/json" \
  -d '{"message":"test"}'

# Should return 200 OK or 202 Accepted
```

---

## Monitoring Checklist

Use this checklist to verify everything is working:

- [ ] Vector service is running (`systemctl status vector`)
- [ ] Vector has curio.log open (`lsof -p $(pgrep vector) | grep curio`)
- [ ] No errors in Vector logs (`journalctl -u vector -n 50`)
- [ ] /var/log/curio/ has proper permissions - 755 (`ls -ld /var/log/curio/`)
- [ ] curio.log has proper permissions - 644 (`ls -l /var/log/curio/curio.log`)
- [ ] curio.log is JSON formatted (`head -1 /var/log/curio/curio.log`)
- [ ] New logs appear in Better Stack within 2 minutes
- [ ] client_id field is visible in Better Stack logs
- [ ] Can filter by `client_id:"your-id"` in Better Stack
- [ ] CPU usage is <5% (`ps aux | grep vector`)
- [ ] Memory usage is <200MB (`ps aux | grep vector`)

---

## Getting Help

If you've tried all troubleshooting steps and it's still not working:

**Gather this info:**

```bash
# 1. Vector status
sudo systemctl status vector > vector-status.txt

# 2. Recent logs
sudo journalctl -u vector -n 100 > vector-logs.txt

# 3. Config (redact token first!)
sudo cat /etc/vector/vector.yaml | sed 's/LzoJaWSF4bbA4ic1JEeQ4TK7/REDACTED/' > vector-config.txt

# 4. Permissions
ls -ld /var/log/curio/ > permissions.txt
groups vector >> permissions.txt
ls -l /var/log/curio/curio.log >> permissions.txt
```

**Contact:**
- File a GitHub issue with the above files
- Include your client_id
- Describe what you've already tried
