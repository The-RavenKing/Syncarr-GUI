# Syncarr Web GUI

A modern web-based GUI for managing [Syncarr](https://github.com/syncarr/syncarr) sync jobs between Radarr, Sonarr, and Lidarr instances.

![Syncarr Web GUI](https://img.shields.io/badge/Python-3.8+-blue) ![FastAPI](https://img.shields.io/badge/FastAPI-0.100+-green) ![License](https://img.shields.io/badge/License-MIT-yellow)

## Features

- **Multi-Job Support**: Create and manage multiple sync jobs
- **Dashboard**: View all jobs with status, last run time, and controls
- **Test Connections**: Independently test Source and Destination connections
- **Fetch Profiles & Paths**: Auto-fetch available profiles and root folders from your *arr instances
- **Bidirectional Sync**: Sync content both ways between instances
- **Debug Logging**: Enable verbose logging for troubleshooting
- **Per-Job Logs**: View logs for each sync job
- **Run Now**: Manually trigger any job
- **Authentication**: Simple username/password login
- **Configurable Port**: Change the web GUI port from settings

---

## Requirements

- Python 3.8 or higher
- Syncarr source files (included in `syncarr_source/`)

---

## Installation

### 1. Clone or Download

```bash
git clone https://github.com/YOUR_USERNAME/syncarr-web-gui.git
cd syncarr-web-gui
```

### 2. Install Python Dependencies

```bash
pip install -r requirements_gui.txt
```

### 3. Run the Web GUI

**Windows:**
```bash
start.bat
```

**Linux/Mac:**
```bash
python web_app.py
```

### 4. Access the GUI

Open your browser and go to:
```
http://localhost:8000
```

Default login:
- **Username:** `admin`
- **Password:** `admin`

> ⚠️ **Change the default password** in Settings after first login!

---

## Configuration

### Changing the Port

1. Go to **Settings** tab
2. Enter new port number
3. Click **Update Port**
4. Restart the application

### Changing Login Credentials

1. Go to **Settings** tab
2. Enter new username and password
3. Click **Update Credentials**

---

## Usage

### Creating a Sync Job

1. Click **+ New Job** on the Dashboard
2. Enter a **Job Name**
3. Select **Type** (Radarr, Sonarr, or Lidarr)
4. Set **Sync Interval** in minutes
5. Configure **Instance A (Source)**:
   - Enter URL (e.g., `http://192.168.1.100:7878`)
   - Enter API Key
6. Configure **Instance B (Destination)**:
   - Enter URL
   - Enter API Key
   - Click **Fetch** to load available Profiles and Root Folders
   - Select or type the Profile Name and Root Path
7. *Optional:* Enable **Bidirectional Sync** (requires Profile/Path for Instance A too)
8. *Optional:* Enable **Debug Logging** for verbose output
9. Click **Save Job**

### Testing Connections

- **Test Source**: Tests connection to Instance A
- **Test Dest**: Tests connection to Instance B

You must save the job first before testing.

### Running a Job Manually

Click **Run Now** on any job card to immediately trigger a sync.

### Viewing Logs

1. Click **View Logs** on a job card
2. Go to the **Logs** tab
3. Click **Refresh** to update logs
4. Click **Clear View** to reset the log display

---

## File Structure

```
syncarr-web-gui/
├── web_app.py              # Main FastAPI application
├── scheduler.py            # Background job scheduler
├── requirements_gui.txt    # Python dependencies
├── start.bat               # Windows startup script
├── gui_config.json         # GUI configuration (port, auth)
├── jobs.json               # Saved sync jobs
├── routers/
│   ├── auth.py             # Authentication endpoints
│   ├── jobs.py             # Job management API
│   └── system.py           # System endpoints
├── static/
│   └── index.html          # Frontend UI
└── syncarr_source/         # Original Syncarr sync scripts
    ├── index.py
    ├── config.py
    └── ...
```

---

## API Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/token` | Login and get access token |
| GET | `/api/jobs` | List all jobs |
| POST | `/api/jobs` | Create a new job |
| PUT | `/api/jobs/{id}` | Update a job |
| DELETE | `/api/jobs/{id}` | Delete a job |
| POST | `/api/jobs/{id}/test` | Test Instance A connection |
| POST | `/api/jobs/{id}/test-b` | Test Instance B connection |
| POST | `/api/jobs/{id}/run` | Manually run a job |
| GET | `/api/jobs/{id}/logs` | Get job logs |
| POST | `/api/fetch-profiles` | Fetch profiles from an instance |
| POST | `/api/fetch-rootfolders` | Fetch root folders from an instance |
| POST | `/api/auth/update` | Update credentials |
| POST | `/api/auth/port` | Update GUI port |

---

## Troubleshooting

### Job shows "Error" status

1. Click **View Logs** to see what went wrong
2. Enable **Debug Logging** on the job for more details
3. Common issues:
   - Missing Profile Name or Root Path
   - Invalid API Key
   - Instance not reachable

### "profile_id or profile is required" error

When **Bidirectional Sync** is enabled, you must configure Profile and Root Path for **both** Instance A and Instance B.

### Fetch returns no profiles/folders

- Verify the URL and API Key are correct
- Click **Test Source** or **Test Dest** to check connectivity
- Ensure the URL includes the correct port

---

## License

MIT License - See [LICENSE](LICENSE) for details.

---

## Credits

- Original [Syncarr](https://github.com/syncarr/syncarr) by the Syncarr team
- Web GUI developed with [FastAPI](https://fastapi.tiangolo.com/) and [Alpine.js](https://alpinejs.dev/)
