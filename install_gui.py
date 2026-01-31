import subprocess
import sys
import os

def install():
    print("Installing dependencies from requirements_gui.txt...")
    try:
        subprocess.check_call([sys.executable, "-m", "pip", "install", "-r", "requirements_gui.txt"])
        print("Dependencies installed successfully.")
    except subprocess.CalledProcessError as e:
        print(f"Error installing dependencies: {e}")
        sys.exit(1)

if __name__ == "__main__":
    if not os.path.exists("requirements_gui.txt"):
        print("requirements_gui.txt not found!")
        sys.exit(1)
    install()
    print("Setup complete. You can now run the GUI with: python web_app.py")
