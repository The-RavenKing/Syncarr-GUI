from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer, OAuth2PasswordRequestForm
from pydantic import BaseModel
from datetime import datetime, timedelta
from typing import Optional
import os
import json
import jwt

router = APIRouter()

GUI_CONFIG_FILE = "gui_config.json"

def load_gui_config():
    if os.path.exists(GUI_CONFIG_FILE):
        with open(GUI_CONFIG_FILE, 'r') as f:
            return json.load(f)
    return {
        "port": 8000,
        "auth_users": {"admin": "admin"},
        "secret_key": "syncarr_secret_key_change_me"
    }

def save_gui_config(config):
    with open(GUI_CONFIG_FILE, 'w') as f:
        json.dump(config, f, indent=4)

gui_config = load_gui_config()
SECRET_KEY = gui_config.get("secret_key", "syncarr_secret_key_change_me")
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = 300

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="token")

class Token(BaseModel):
    access_token: str
    token_type: str

class TokenData(BaseModel):
    username: Optional[str] = None

class UserUpdate(BaseModel):
    username: str
    password: str

def create_access_token(data: dict, expires_delta: Optional[timedelta] = None):
    to_encode = data.copy()
    if expires_delta:
        expire = datetime.utcnow() + expires_delta
    else:
        expire = datetime.utcnow() + timedelta(minutes=15)
    to_encode.update({"exp": expire})
    encoded_jwt = jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)
    return encoded_jwt

async def get_current_user(token: str = Depends(oauth2_scheme)):
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Could not validate credentials",
        headers={"WWW-Authenticate": "Bearer"},
    )
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        username: str = payload.get("sub")
        if username is None:
            raise credentials_exception
        token_data = TokenData(username=username)
    except jwt.PyJWTError:
        raise credentials_exception
    return token_data

@router.post("/token", response_model=Token)
async def login_for_access_token(form_data: OAuth2PasswordRequestForm = Depends()):
    gui_config = load_gui_config() # Reload to get latest
    users = gui_config.get("auth_users", {})
    
    user_password = users.get(form_data.username)
    if not user_password or user_password != form_data.password:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect username or password",
            headers={"WWW-Authenticate": "Bearer"},
        )
    access_token_expires = timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
    access_token = create_access_token(
        data={"sub": form_data.username}, expires_delta=access_token_expires
    )
    return {"access_token": access_token, "token_type": "bearer"}

@router.get("/users/me")
async def read_users_me(current_user: TokenData = Depends(get_current_user)):
    return current_user

@router.post("/api/auth/update")
async def update_auth(user_data: UserUpdate, current_user: TokenData = Depends(get_current_user)):
    config = load_gui_config()
    users = config.get("auth_users", {})
    
    if current_user.username in users:
        del users[current_user.username]
        
    users[user_data.username] = user_data.password
    config["auth_users"] = users
    
    # Check if port was passed? 
    # The model UserUpdate only has username/password.
    # We should update the model or just handle it if we change the model.
    # Let's keep it simple for now, but user asked for port update in UI.
    # We should add a separate endpoint or extend this one.
    
    save_gui_config(config)
    return {"status": "success", "message": "Credentials updated"}

class PortUpdate(BaseModel):
    port: int

@router.post("/api/auth/port")
async def update_port(port_data: PortUpdate, current_user: TokenData = Depends(get_current_user)):
    config = load_gui_config()
    config["port"] = port_data.port
    save_gui_config(config)
    return {"status": "success", "message": "Port updated. Restart required."}
