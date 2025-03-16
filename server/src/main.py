import uvicorn
import argparse
import base64
import secrets
from fastapi import FastAPI, Depends, HTTPException, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.security import HTTPBasic, HTTPBasicCredentials
from src.api.router import router
from src.utils.database import init_db

# Parse command line arguments
parser = argparse.ArgumentParser(description="LLM Chat API Server")
parser.add_argument("-d", "--static-dir", help="Static directory to serve as web root", default=None)
parser.add_argument("-p", "--password", help="Password for Basic Authentication", default=None)
args = parser.parse_args()

app = FastAPI(title="LLM Chat API")

# Setup Basic Auth if password is provided
security = HTTPBasic()

def get_current_username(credentials: HTTPBasicCredentials = Depends(security)):
    if args.password is None:
        return "anonymous"
        
    correct_password = args.password
    is_correct = secrets.compare_digest(credentials.password, correct_password)
    
    if not is_correct:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid authentication credentials",
            headers={"WWW-Authenticate": "Basic"},
        )
    return credentials.username

# Function for WebSocket authentication
def verify_ws_password(auth_header: str) -> bool:
    """Verify WebSocket authentication header against the password."""
    if args.password is None:
        return True
        
    if not auth_header or not auth_header.startswith('Basic '):
        return False
        
    try:
        auth_decoded = base64.b64decode(auth_header[6:]).decode('utf-8')
        username, password = auth_decoded.split(':', 1)
        return secrets.compare_digest(password, args.password)
    except Exception:
        return False

# Configure CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # In production, replace with specific origins
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Include routers with optional authentication
if args.password:
    print(f"Basic authentication enabled")
    app.include_router(router, dependencies=[Depends(get_current_username)])
else:
    app.include_router(router)

# Mount static directory if specified
if args.static_dir:
    print(f"Serving static files from: {args.static_dir}")
    app.mount("/", StaticFiles(directory=args.static_dir, html=True), name="static")

@app.on_event("startup")
async def startup():
    await init_db()

if __name__ == "__main__":
    uvicorn.run("src.main:app", host="0.0.0.0", port=8035, reload=True)
