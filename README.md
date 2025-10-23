# Warp Speed Log Streaming

**One-command centralized logging for Curio PDP nodes**

Stream your Curio PDP logs to Better Stack for easy debugging, monitoring, and collaboration across the network.

---

## ⚠️ Important

This logging infrastructure is set up to help maintainers and the core filecoin onchain cloud working group debug issues with new software being actively developed as part of [Filecoin Onchain Cloud](https://filecoin.cloud/) (FOC). **This is NOT a white-glove support service for SPs.**

**Intended Audience**: SPX SPs participating in the Warp Speed program and early SPs involved with getting FOC off the ground who are using the PDP Curio branch.

---

## Prerequisites

- **Better Stack token** - Contact the FilOz team in the **#fil-pdp** channel on Filecoin Slack to receive your Better Stack token. This token is shared among all Warp Speed participants and should not be publicly shared.
- **Bash shell** (required for installer)
- **Curio** running (systemd service or manual)
- **Sudo access** (for installing Vector and configuring systemd)
- **Your client ID** from the [Filecoin Service Registry](https://www.filecoin.services/providers)


## Install

**One command to rule them all:**

```bash
curl -sSL https://raw.githubusercontent.com/FilOzone/warp-speed-log-streaming/main/install.sh | bash
```

The installer will prompt you for:
- Your client ID (from Filecoin Service Registry, e.g., `YOUR_CLIENT_ID="ezpdpz-calib"`)
- Better Stack token (provided by maintainer)

**Time:** ~30-60 seconds

---

### What It Does

The installer:
1. Prompts for your client ID
2. Prompts for Better Stack token
3. Detects your deployment method (systemd vs manual)
4. Sets up logging configuration (if manual)
5. Installs Vector (if needed)
6. Configures log streaming
7. Starts the service
8. Verifies everything works


### Deployment Methods

The installer supports two deployment methods and auto-detects which you're using:

#### Method 1: Systemd Service (Recommended)

If running Curio as a systemd service, ensure your service file has:
```ini
[Service]
Environment=GOLOG_FILE="/var/log/curio/curio.log"
Environment=GOLOG_LOG_FMT="json"
```

The installer will detect the systemd service and verify the log file exists.

#### Method 2: Manual Deployment

If running Curio manually (not as systemd), the installer will:
- Create `/var/log/curio/` directory
- Add environment variables to `/etc/profile.d/curio-logging.sh` (shell-agnostic):
  - `GOLOG_OUTPUT="file+stdout"` (logs to both file and terminal)
  - `GOLOG_FILE="/var/log/curio/curio.log"`
  - `GOLOG_LOG_FMT="json"`

You'll need to source the configuration (`source /etc/profile.d/curio-logging.sh` or start a new shell) and restart Curio for the changes to take effect.

---

## Verification

After installation, verify it's working:

```bash
# Check Vector status
sudo systemctl status vector

# Watch logs being processed
sudo journalctl -u vector -f

# Look for this message:
# "Found new file to watch. file=/path/to/curio.log"
```

Logs appear in the Better Stack dashboard within ~1 minute.

Filter by your client ID: `client_id:"$YOUR_CLIENT_ID"`

---

## Troubleshooting

### Vector not starting

```bash
# Check for config errors
sudo vector validate --config /etc/vector/vector.yaml

# Check logs
sudo journalctl -u vector -n 50
```

### No logs appearing in Better Stack

**Wait 1-2 minutes** - Batching means logs are sent in groups

**Check if Vector is reading the file:**
```bash
sudo lsof -p $(pgrep vector) | grep curio.log
```

If the file is NOT open, Vector likely doesn't have permission:
```bash
# Check and fix permissions
sudo chmod 755 /var/log/curio/
sudo chmod 644 /var/log/curio/curio.log
sudo systemctl restart vector
```

### Permission denied errors

```bash
# Check log directory permissions
ls -ld /var/log/curio/
ls -l /var/log/curio/curio.log

# Directory should be 755 and file should be 644
# If not, fix permissions:
sudo chmod 755 /var/log/curio/
sudo chmod 644 /var/log/curio/curio.log

# Restart Vector
sudo systemctl restart vector
```

---

## Uninstall

To remove Vector and stop log streaming:

```bash
sudo systemctl stop vector
sudo systemctl disable vector
sudo apt remove vector  # or: brew uninstall vector
```

---

## Architecture

```
Curio PDP Node
  ↓
curio.log (JSON format)
  ↓
Vector (reads, parses, batches)
  ↓
Better Stack (centralized logs)
```

**Data flow:**
1. Curio writes JSON logs to file
2. Vector tails the file
3. Parses JSON and adds client_id
4. Batches 1000 events or 10 seconds (see [vector.yaml](vector.yaml))
5. Compresses with gzip
6. POSTs to Better Stack

**Security:**
- Logs sent over HTTPS
- Authenticated with Bearer token
- Vector runs as limited `vector` user

---

## Configuration

The Vector config is at `/etc/vector/vector.yaml`

Key settings:
- **Source**: Tails your curio.log file
- **Transform**: Parses JSON, adds client_id and platform fields
- **Sink**: Sends to Better Stack via HTTP
- **Batching**: 1000 events or 10 seconds (whichever comes first) - see [vector.yaml](vector.yaml) for details

---

## Cost

- **Better Stack**: Shared across all SPs (~$29/month total, not per-SP)
- **Bandwidth**: ~minimal (gzip compressed, batched)
- **CPU/Memory**: Vector is lightweight (~50MB RAM, <1% CPU)

---

## Privacy & Data Protection

We take privacy seriously. The logging system:
- **Filters hostname** from logs (though already in public registry)
- **Filters filepath** information
- **Does not track or store IP addresses**
- **Dashboard access** limited to working group/maintainers only (not public)

---

## Support

**Issues or questions?**

- File an issue: [GitHub Issues](https://github.com/FilOzone/warp-speed-log-streaming/issues)
- Contact PDP maintainers in [#fil-pdp] with:
  - Your client ID
  - Output of `sudo systemctl status vector`
  - Recent logs: `sudo journalctl -u vector -n 100`

---

## Related

- **Better Stack Dashboard**: https://s1560290.eu-nbg-2.betterstackdata.com (access limited to working group/maintainers)
- **Vector Docs**: https://vector.dev/docs/
- **Curio PDP Docs**: https://docs.curiostorage.org/experimental-features/enable-pdp
- **Filecoin Service Registry**: https://filecoin.services/providers

---

## License

MIT License - See LICENSE file
