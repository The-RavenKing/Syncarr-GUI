import json
import os
import shutil
import threading
import time
from datetime import datetime

# Define the absolute path to the jobs file
# This ensures it's always found regardless of where the app is started from
BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
JOBS_FILE = os.path.join(BASE_DIR, "jobs.json")
BACKUP_FILE = os.path.join(BASE_DIR, "jobs.json.bak")

# Simple lock for thread safety within the process
_file_lock = threading.Lock()

def load_jobs():
    """
    Load jobs from the JSON file with thread safety.
    Returns an empty list if the file doesn't exist or is invalid.
    """
    with _file_lock:
        if not os.path.exists(JOBS_FILE):
            return []
            
        try:
            with open(JOBS_FILE, 'r') as f:
                return json.load(f)
        except json.JSONDecodeError:
            print(f"Error decoding {JOBS_FILE}. Attempting to restore backup.")
            return _restore_backup()
        except Exception as e:
            print(f"Error loading jobs: {e}")
            return []

def save_jobs(jobs):
    """
    Save jobs to the JSON file with thread safety and atomic write.
    Creates a backup of the existing file before overwriting.
    """
    with _file_lock:
        try:
            # 1. Create a backup if the file exists
            if os.path.exists(JOBS_FILE):
                try:
                    shutil.copy2(JOBS_FILE, BACKUP_FILE)
                except Exception as e:
                    print(f"Warning: Failed to create backup: {e}")

            # 2. Write to a temporary file first
            temp_file = JOBS_FILE + ".tmp"
            with open(temp_file, 'w') as f:
                json.dump(jobs, f, indent=4)
                f.flush()
                os.fsync(f.fileno()) # Ensure data is written to disk

            # 3. Rename temporary file to actual file (atomic operation on POSIX, usually safe on Windows)
            if os.path.exists(JOBS_FILE):
                os.remove(JOBS_FILE)
            os.rename(temp_file, JOBS_FILE)
            
            return True
        except Exception as e:
            print(f"Error saving jobs: {e}")
            if os.path.exists(temp_file):
                try:
                    os.remove(temp_file)
                except:
                    pass
            return False

def _restore_backup():
    """
    Attempts to restore from backup file.
    """
    if os.path.exists(BACKUP_FILE):
        try:
            shutil.copy2(BACKUP_FILE, JOBS_FILE)
            with open(JOBS_FILE, 'r') as f:
                return json.load(f)
        except Exception as e:
            print(f"Error restoring backup: {e}")
    return []

def update_job_status(job_id, status, last_run=None):
    """
    Updates the status of a specific job.
    """
    # We need to load, update, and save within the lock to prevent lost updates
    # But since load_jobs and save_jobs have their own locks, we should implement
    # a specific update function that holds the lock for the duration.
    
    with _file_lock:
        jobs = []
        if os.path.exists(JOBS_FILE):
            try:
                with open(JOBS_FILE, 'r') as f:
                    jobs = json.load(f)
            except:
                pass # Handle error or return
        
        updated = False
        for job in jobs:
            if job['id'] == job_id:
                job['status'] = status
                if last_run:
                    job['last_run'] = last_run
                updated = True
                break
        
        if updated:
            try:
                # Write logic duplicated here to avoid re-acquiring lock if we used save_jobs
                # or we could make save_jobs support an external lock.
                # simpler to just write here for now or extract the write logic.
                
                temp_file = JOBS_FILE + ".tmp"
                with open(temp_file, 'w') as f:
                    json.dump(jobs, f, indent=4)
                    f.flush()
                    os.fsync(f.fileno())
                
                if os.path.exists(JOBS_FILE):
                    os.remove(JOBS_FILE)
                os.rename(temp_file, JOBS_FILE)
            except Exception as e:
                print(f"Error updating job status: {e}")
