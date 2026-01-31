from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
import configparser
import os
from .auth import get_current_user

router = APIRouter()

CONFIG_FILE = "syncarr_source/config.conf"

class ConfigSection(BaseModel):
    section_name: str
    data: dict

@router.get("/api/config")
async def get_config(current_user: dict = Depends(get_current_user)):
    if not os.path.exists(CONFIG_FILE):
        return {"error": "Config file not found"}
    
    config = configparser.ConfigParser()
    config.read(CONFIG_FILE)
    
    result = {}
    for section in config.sections():
        result[section] = dict(config[section])
    
    return result

@router.post("/api/config")
async def update_config(config_data: dict, current_user: dict = Depends(get_current_user)):
    if not os.path.exists(CONFIG_FILE):
        raise HTTPException(status_code=404, detail="Config file not found")
    
    config = configparser.ConfigParser()
    config.read(CONFIG_FILE)
    
    for section, values in config_data.items():
        if not config.has_section(section):
            config.add_section(section)
        for key, value in values.items():
            config.set(section, key, str(value))
            
    with open(CONFIG_FILE, 'w') as configfile:
        config.write(configfile)
        
    return {"status": "success", "message": "Config updated"}

@router.delete("/api/config/{section}")
async def delete_section(section: str, current_user: dict = Depends(get_current_user)):
    if not os.path.exists(CONFIG_FILE):
        raise HTTPException(status_code=404, detail="Config file not found")
        
    config = configparser.ConfigParser()
    config.read(CONFIG_FILE)
    
    if not config.has_section(section):
         raise HTTPException(status_code=404, detail="Section not found")
         
    config.remove_section(section)
    
    with open(CONFIG_FILE, 'w') as configfile:
        config.write(configfile)
        
    return {"status": "success", "message": f"Section {section} deleted"}

class SectionCreate(BaseModel):
    name: str

@router.post("/api/config/section")
async def create_section(section_data: SectionCreate, current_user: dict = Depends(get_current_user)):
    if not os.path.exists(CONFIG_FILE):
        raise HTTPException(status_code=404, detail="Config file not found")

    config = configparser.ConfigParser()
    config.read(CONFIG_FILE)
    
    section_name = section_data.name
    
    if config.has_section(section_name):
        raise HTTPException(status_code=400, detail="Section already exists")
        
    config.add_section(section_name)
    
    # Add default keys based on type? Or just empty.
    # Syncarr seems to need url/key at minimum.
    # Let's just create empty and let UI populate.
    
    with open(CONFIG_FILE, 'w') as configfile:
        config.write(configfile)
        
    return {"status": "success", "message": f"Section {section_name} created"}
