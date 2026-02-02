from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from typing import List, Dict, Optional, Any
import json
import os
import uuid
import requests
from datetime import datetime
from .auth import get_current_user
import scheduler
import threading

router = APIRouter()

JOBS_FILE = "jobs.json"

class JobConfig(BaseModel):
    # Common fields
    url_a: str
    key_a: str
    url_b: str
    key_b: str
    # Radarr/Sonarr specific
    profile_b: Optional[str] = None
    path_b: Optional[str] = None
    # We can add more specific fields if needed, but for now we map these to ENV vars

class Job(BaseModel):
    id: Optional[str] = None
    name: str
    type: str # radarr, sonarr, lidarr
    interval_minutes: int
    config: Dict[str, Any] # Store raw ENV vars mapping or structured config
    last_run: Optional[str] = "Never"
    status: Optional[str] = "Idle" # Idle, Running, Error

def load_jobs():
    if os.path.exists(JOBS_FILE):
        with open(JOBS_FILE, 'r') as f:
            try:
                return json.load(f)
            except json.JSONDecodeError:
                return []
    return []

def save_jobs(jobs):
    with open(JOBS_FILE, 'w') as f:
        json.dump(jobs, f, indent=4)

@router.get("/api/jobs", response_model=List[Job])
async def get_jobs(current_user: dict = Depends(get_current_user)):
    return load_jobs()

@router.post("/api/jobs")
async def create_job(job: Job, current_user: dict = Depends(get_current_user)):
    jobs = load_jobs()
    if not job.id:
        job.id = str(uuid.uuid4())
    
    # Ensure config dict is populated correctly based on type if passed as structured
    # For simplicity, we assume frontend passes the ENV var mapping in 'config' 
    # OR we map it here. Let's map it here to keep frontend simple.
    # Actually, let's let frontend pass a "structured" config in the Job model 
    # and we convert it to the ENV vars the script expects.
    
    # BUT, the Job model 'config' field is Dict[str, str].
    # Let's assume the frontend sends the specific keys we need like "url_a", "key_a" etc
    # and we trust it, or we transform it.
    # The syncarr script needs specific ENV keys.
    # Let's trust the frontend to send the right keys or we map them in the scheduler.
    # Storing them as semantic keys (url_a) is better for UI.
    
    jobs.append(job.dict())
    save_jobs(jobs)
    return job

@router.put("/api/jobs/{job_id}")
async def update_job(job_id: str, job: Job, current_user: dict = Depends(get_current_user)):
    jobs = load_jobs()
    for i, j in enumerate(jobs):
        if j['id'] == job_id:
            job.id = job_id # ensure ID matches
            jobs[i] = job.dict()
            save_jobs(jobs)
            return job
    raise HTTPException(status_code=404, detail="Job not found")

@router.delete("/api/jobs/{job_id}")
async def delete_job(job_id: str, current_user: dict = Depends(get_current_user)):
    jobs = load_jobs()
    jobs = [j for j in jobs if j['id'] != job_id]
    save_jobs(jobs)
    return {"status": "success"}

@router.post("/api/jobs/{job_id}/test")
async def test_connection(job_id: str, current_user: dict = Depends(get_current_user)):
    # Load job to get config
    jobs = load_jobs()
    job = next((j for j in jobs if j['id'] == job_id), None)
    if not job:
         # If checking new job, maybe pass config in body? 
         # For now assume saved job.
         raise HTTPException(status_code=404, detail="Job not found")
    
    config = job['config']
    # Config is expected to have 'url_a', 'key_a', 'type'
    
    type_ = job['type']
    url = config.get('url_a')
    key = config.get('key_a')
    skip_ssl = config.get('skip_ssl_verify', False)
    
    if not url or not key:
        return {"status": "error", "message": "URL or Key missing"}

    if not url.startswith("http://") and not url.startswith("https://"):
        url = "http://" + url
        
    api_path = "/api/v3/system/status"
    if type_ == 'lidarr':
        api_path = "/api/v1/system/status"
        
    try:
        # Simple verify of Instance A
        res = requests.get(f"{url}{api_path}", params={"apikey": key}, timeout=30, verify=not skip_ssl)
        if res.status_code == 200:
            return {"status": "success", "message": "Connection to Instance A successful"}
        else:
             return {"status": "error", "message": f"Instance A returned {res.status_code}"}
    except Exception as e:
        return {"status": "error", "message": str(e)}

@router.post("/api/jobs/{job_id}/test-b")
async def test_connection_b(job_id: str, current_user: dict = Depends(get_current_user)):
    jobs = load_jobs()
    job = next((j for j in jobs if j['id'] == job_id), None)
    if not job:
         raise HTTPException(status_code=404, detail="Job not found")
    
    config = job['config']
    type_ = job['type']
    url = config.get('url_b')
    key = config.get('key_b')
    skip_ssl = config.get('skip_ssl_verify', False)
    
    if not url or not key:
        return {"status": "error", "message": "URL or Key missing for Instance B"}

    if not url.startswith("http://") and not url.startswith("https://"):
        url = "http://" + url
        
    api_path = "/api/v3/system/status"
    if type_ == 'lidarr':
        api_path = "/api/v1/system/status"
        
    try:
        res = requests.get(f"{url}{api_path}", params={"apikey": key}, timeout=30, verify=not skip_ssl)
        if res.status_code == 200:
            return {"status": "success", "message": "Connection to Instance B successful"}
        else:
             return {"status": "error", "message": f"Instance B returned {res.status_code}"}
    except Exception as e:
        return {"status": "error", "message": str(e)}

class FetchProfilesRequest(BaseModel):
    url: str
    key: str
    type: str # radarr, sonarr, lidarr
    skip_ssl_verify: Optional[bool] = False

@router.post("/api/fetch-profiles")
async def fetch_profiles(req: FetchProfilesRequest, current_user: dict = Depends(get_current_user)):
    url = req.url
    key = req.key
    type_ = req.type
    skip_ssl = req.skip_ssl_verify or False
    
    if not url or not key:
        return {"status": "error", "profiles": [], "message": "URL or Key missing"}

    if not url.startswith("http://") and not url.startswith("https://"):
        url = "http://" + url
    
    # Remove trailing slash
    url = url.rstrip('/')
        
    api_path = "/api/v3/qualityprofile"
    if type_ == 'lidarr':
        api_path = "/api/v1/qualityprofile"
        
    try:
        res = requests.get(f"{url}{api_path}", params={"apikey": key}, timeout=30, verify=not skip_ssl)
        if res.status_code == 200:
            profiles = res.json()
            profile_names = [p.get('name') for p in profiles]
            return {"status": "success", "profiles": profile_names}
        else:
             return {"status": "error", "profiles": [], "message": f"Server returned {res.status_code}"}
    except Exception as e:
        return {"status": "error", "profiles": [], "message": str(e)}

@router.post("/api/fetch-rootfolders")
async def fetch_rootfolders(req: FetchProfilesRequest, current_user: dict = Depends(get_current_user)):
    url = req.url
    key = req.key
    type_ = req.type
    skip_ssl = req.skip_ssl_verify or False
    
    if not url or not key:
        return {"status": "error", "folders": [], "message": "URL or Key missing"}

    if not url.startswith("http://") and not url.startswith("https://"):
        url = "http://" + url
    
    url = url.rstrip('/')
        
    api_path = "/api/v3/rootfolder"
    if type_ == 'lidarr':
        api_path = "/api/v1/rootfolder"
        
    try:
        res = requests.get(f"{url}{api_path}", params={"apikey": key}, timeout=30, verify=not skip_ssl)
        if res.status_code == 200:
            folders = res.json()
            folder_paths = [f.get('path') for f in folders]
            return {"status": "success", "folders": folder_paths}
        else:
             return {"status": "error", "folders": [], "message": f"Server returned {res.status_code}"}
    except Exception as e:
        return {"status": "error", "folders": [], "message": str(e)}

@router.get("/api/jobs/{job_id}/logs")
async def get_job_logs(job_id: str, current_user: dict = Depends(get_current_user)):
    logs = scheduler.get_job_logs(job_id)
    return {"logs": logs}

@router.get("/api/jobs/{job_id}/progress")
async def get_job_progress(job_id: str, current_user: dict = Depends(get_current_user)):
    progress = scheduler.get_job_progress(job_id)
    if progress:
        return {"has_progress": True, **progress}
    return {"has_progress": False}

@router.post("/api/jobs/{job_id}/run")
async def run_job_endpoint(job_id: str, current_user: dict = Depends(get_current_user)):
    jobs = scheduler.load_jobs()
    job = next((j for j in jobs if j['id'] == job_id), None)
    if not job:
        raise HTTPException(status_code=404, detail="Job not found")
    
    # Run in background via scheduler logic?
    # Or start thread directly?
    # Scheduler's run_job is a standalone function.
    threading.Thread(target=scheduler.run_job, args=(job,)).start()
    
    return {"status": "success", "message": "Job started"}


# ============== UPDATE FUNCTIONALITY ==============

import shutil
import subprocess
import sys

# Try to detect the source path (network share or git repo)
def get_source_path():
    """Try to find the source installation path"""
    possible_sources = [
        r"\\192.168.1.228\Video\Syncarr Front-end\Syncarr-GUI",
        os.path.join(os.path.dirname(os.path.dirname(__file__)), ".."),  # Parent of current
    ]
    for src in possible_sources:
        if os.path.exists(os.path.join(src, "syncarr_source", "index.py")):
            return src
    return None

@router.post("/api/update")
async def update_syncarr(current_user: dict = Depends(get_current_user)):
    """Update Syncarr from source directory"""
    
    source_path = get_source_path()
    if not source_path:
        return {"status": "error", "message": "Could not find source installation path"}
    
    install_path = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    
    # Don't update if running from source directly
    if os.path.normpath(source_path) == os.path.normpath(install_path):
        return {"status": "error", "message": "Already running from source. Use 'git pull' to update."}
    
    items_to_update = [
        "syncarr_source",
        "static",
        "routers",
        "scheduler.py",
        "web_app.py",
    ]
    
    updated_items = []
    errors = []
    
    try:
        for item in items_to_update:
            src = os.path.join(source_path, item)
            dst = os.path.join(install_path, item)
            
            if os.path.exists(src):
                try:
                    if os.path.isdir(src):
                        if os.path.exists(dst):
                            shutil.rmtree(dst)
                        shutil.copytree(src, dst)
                    else:
                        shutil.copy2(src, dst)
                    updated_items.append(item)
                except Exception as e:
                    errors.append(f"{item}: {str(e)}")
        
        if errors:
            return {
                "status": "partial",
                "message": f"Updated {len(updated_items)} items with {len(errors)} errors",
                "updated": updated_items,
                "errors": errors,
                "restart_required": True
            }
        
        return {
            "status": "success",
            "message": f"Updated {len(updated_items)} items. Restart the service to apply changes.",
            "updated": updated_items,
            "restart_required": True
        }
        
    except Exception as e:
        return {"status": "error", "message": str(e)}


@router.post("/api/restart")
async def restart_service(current_user: dict = Depends(get_current_user)):
    """Schedule a service restart"""
    import time
    
    def delayed_restart():
        time.sleep(2)  # Give time for response to be sent
        try:
            # Try to restart via Windows Service
            subprocess.run(["powershell", "-Command", "Restart-Service", "Syncarr"], 
                          capture_output=True, timeout=30)
        except:
            # Fallback: just exit and let service manager restart
            os._exit(0)
    
    threading.Thread(target=delayed_restart, daemon=True).start()
    return {"status": "success", "message": "Service will restart in 2 seconds..."}
