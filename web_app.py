from fastapi import FastAPI
from fastapi.staticfiles import StaticFiles
from fastapi.responses import RedirectResponse
import uvicorn
import os
import json
import threading

from routers import auth, jobs, system
import scheduler

app = FastAPI(title="Syncarr Web GUI")

# Mount static files
if not os.path.exists("static"):
    os.makedirs("static")
app.mount("/static", StaticFiles(directory="static"), name="static")

# Include routers
app.include_router(auth.router)
app.include_router(jobs.router) # Jobs replace Config
app.include_router(system.router)

@app.get("/")
async def root():
    return RedirectResponse(url="/static/index.html")

def get_port():
    if os.path.exists("gui_config.json"):
        with open("gui_config.json", 'r') as f:
            try:
                config = json.load(f)
                return config.get("port", 8000)
            except:
                pass
    return 8000

if __name__ == "__main__":
    # Start Scheduler
    scheduler.start_scheduler()
    
    port = get_port()
    print(f"Starting server on port {port}...")
    uvicorn.run(app, host="0.0.0.0", port=port)
