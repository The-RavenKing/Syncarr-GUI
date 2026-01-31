import asyncio
import json
import os
import subprocess
import time
import threading
from datetime import datetime, timedelta

JOBS_FILE = "jobs.json"
POLL_INTERVAL = 30 # Check every 30 seconds

running_jobs = {} # track running processes if needed, or just lock

def load_jobs():
    if os.path.exists(JOBS_FILE):
        with open(JOBS_FILE, 'r') as f:
            try:
                return json.load(f)
            except:
                return []
    return []

def save_jobs(jobs):
    with open(JOBS_FILE, 'w') as f:
        json.dump(jobs, f, indent=4)

def update_job_status(job_id, status, last_run=None):
    jobs = load_jobs()
    for job in jobs:
        if job['id'] == job_id:
            job['status'] = status
            if last_run:
                job['last_run'] = last_run
            break
    save_jobs(jobs)

job_logs = {} # In-memory log buffer: {job_id: [lines]}

def get_job_logs(job_id):
    return job_logs.get(job_id, [])

def run_job(job):
    print(f"Starting job: {job['name']}")
    update_job_status(job['id'], "Running")
    
    # Initialize log buffer for this job
    job_logs[job['id']] = []
    
    def log(msg):
        timestamp = datetime.now().strftime("%H:%M:%S")
        line = f"[{timestamp}] {msg}"
        print(f"[Job {job['name']}] {msg}") # Console
        job_logs[job['id']].append(line)

    try:
        # Construct ENV vars for Syncarr script
        env = os.environ.copy()
        env["IS_IN_DOCKER"] = "1"
        env["SYNC_INTERVAL_SECONDS"] = "0" # Run once
        
        type_upper = job['type'].upper() # RADARR, SONARR
        
        config = job['config']
        
        # Bidirectional Sync
        if config.get('bidirectional'):
            env["SYNCARR_BIDIRECTIONAL_SYNC"] = "1"
        else:
            env["SYNCARR_BIDIRECTIONAL_SYNC"] = "0"
            
        # Debug Logging
        if config.get('debug_logging'):
            env["LOG_LEVEL"] = "10" # DEBUG
        else:
            env["LOG_LEVEL"] = "20" # INFO
            
        # Skip Missing Files (default: skip movies without files)
        if config.get('sync_missing', False):
            env["SYNCARR_SKIP_MISSING"] = "0"  # Don't skip - sync all movies
        else:
            env["SYNCARR_SKIP_MISSING"] = "1"  # Skip movies without files
        
        url_a = config.get('url_a', '')
        if url_a and not url_a.startswith("http://") and not url_a.startswith("https://"):
            url_a = "http://" + url_a
            
        url_b = config.get('url_b', '')
        if url_b and not url_b.startswith("http://") and not url_b.startswith("https://"):
            url_b = "http://" + url_b

        env[f"{type_upper}_A_URL"] = url_a
        env[f"{type_upper}_A_KEY"] = config.get('key_a', '')
        env[f"{type_upper}_A_PROFILE"] = config.get('profile_a', '')
        env[f"{type_upper}_A_PATH"] = config.get('path_a', '')
        
        env[f"{type_upper}_B_URL"] = url_b
        env[f"{type_upper}_B_KEY"] = config.get('key_b', '')
        env[f"{type_upper}_B_PROFILE"] = config.get('profile_b', '')
        env[f"{type_upper}_B_PATH"] = config.get('path_b', '')
        
        cwd = "syncarr_source"
        if not os.path.exists(os.path.join(cwd, "index.py")):
             log("Error: index.py not found")
             update_job_status(job['id'], "Error")
             return

        process = subprocess.Popen(
            ["python", "index.py"],
            cwd=cwd,
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1
        )
        
        for line in iter(process.stdout.readline, ''):
            if line:
                log(line.strip())
            else:
                break
                
        process.wait()
        
        if process.returncode == 0:
            log(f"Job completed successfully.")
            update_job_status(job['id'], "Idle", last_run=datetime.now().strftime("%Y-%m-%d %H:%M:%S"))
        else:
            log(f"Job failed with exit code {process.returncode}")
            update_job_status(job['id'], "Error", last_run=datetime.now().strftime("%Y-%m-%d %H:%M:%S"))

    except Exception as e:
        log(f"Error running job: {e}")
        update_job_status(job['id'], "Error")

def scheduler_loop():
    print("Scheduler started.")
    while True:
        try:
            jobs = load_jobs()
            now = datetime.now()
            
            for job in jobs:
                # Check eligibility
                last_run_str = job.get('last_run')
                interval = job.get('interval_minutes', 60)
                
                should_run = False
                if last_run_str == "Never" or not last_run_str:
                     should_run = True # Auto-run new jobs immediately
                else:
                    try:
                        last_run = datetime.strptime(last_run_str, "%Y-%m-%d %H:%M:%S")
                        next_run = last_run + timedelta(minutes=int(interval))
                        if now >= next_run and job.get('status') != "Running":
                            should_run = True
                    except ValueError:
                        pass 
                
                if should_run:
                   t = threading.Thread(target=run_job, args=(job,))
                   t.start()
                   
        except Exception as e:
            print(f"Scheduler error: {e}")
            
        time.sleep(POLL_INTERVAL)

def start_scheduler():
    t = threading.Thread(target=scheduler_loop, daemon=True)
    t.start()
