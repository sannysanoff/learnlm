import uvicorn
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from src.api.router import router
from src.utils.database import init_db

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

@app.on_event("startup")
async def startup():
    await init_db()

if __name__ == "__main__":
    uvicorn.run("src.main:app", host="0.0.0.0", port=8035, reload=True)
