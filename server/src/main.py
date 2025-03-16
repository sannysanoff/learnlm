import uvicorn
import argparse
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from src.api.router import router
from src.utils.database import init_db

# Parse command line arguments
parser = argparse.ArgumentParser(description="LLM Chat API Server")
parser.add_argument("-d", "--static-dir", help="Static directory to serve as web root", default=None)
args = parser.parse_args()

app = FastAPI(title="LLM Chat API")

# Configure CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # In production, replace with specific origins
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Include routers
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
