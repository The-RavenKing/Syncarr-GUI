from fastapi import APIRouter, WebSocket, Depends
from fastapi.websockets import WebSocketDisconnect
from .auth import get_current_user
import asyncio
import subprocess
import os

router = APIRouter()

@router.websocket("/ws/logs")
async def websocket_endpoint(websocket: WebSocket):
    await websocket.accept()
    process = None
    try:
        # Command to run Syncarr
        # Assuming we run it from the root directory where `install_gui.py` is, 
        # and syncarr source is in `syncarr_source`
        # index.py is in `syncarr_source/index.py`
        
        cwd = "syncarr_source"
        cmd = ["python", "index.py"]
        
        if not os.path.exists(os.path.join(cwd, "index.py")):
             await websocket.send_text(f"Error: index.py not found in {cwd}")
             await websocket.close()
             return

        process = subprocess.Popen(
            cmd,
            cwd=cwd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1  # Line buffered
        )

        # Read output line by line and send to websocket
        for line in iter(process.stdout.readline, ''):
            if line:
                await websocket.send_text(line)
            else:
                break
                
        await websocket.send_text("Process finished.")
        process.wait()

    except WebSocketDisconnect:
        if process:
            process.terminate()
            print("Websocket disconnected, process terminated")
    except Exception as e:
         await websocket.send_text(f"Error: {str(e)}")
    finally:
        if process and process.poll() is None:
            process.terminate()

@router.post("/api/run")
async def run_sync_trigger(current_user: dict = Depends(get_current_user)):
    # This might be redundant if the websocket handles the execution and viewing
    # But usually a REST endpoint is good for triggering if we want background 
    # execution without viewing. 
    # For this specific task "executed the command ... and captures the output",
    # the websocket approach is better for "Log Viewer".
    return {"message": "Use the WebSocket connection to run and view logs."}
