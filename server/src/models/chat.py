from typing import List, Literal, Optional, Dict, Any, Union
from pydantic import BaseModel, Field
from datetime import datetime

class ChatMessage(BaseModel):
    role: Literal["system", "user", "assistant"]
    content: str
    timestamp: Optional[str] = None

class ChatHistory(BaseModel):
    system_message: Optional[str] = None
    messages: List[ChatMessage] = []

class ChatRequest(BaseModel):
    history: ChatHistory
    temperature: float = 1.0
    top_p: float = 0.95
    top_k: int = 64
    max_tokens: int = 8192
    user_secret: Optional[str] = None
    chat_id: Optional[int] = None
    title: Optional[str] = None

class SaveChatRequest(BaseModel):
    user_secret: str
    title: str
    history: ChatHistory
    
class ChatListResponse(BaseModel):
    id: int
    title: str
    created_at: str
    updated_at: str
    
class ChatResponse(BaseModel):
    id: int
    title: str
    created_at: str
    updated_at: str
    messages: List[ChatMessage]
    
    class Config:
        # Allow extra fields in model instances
        extra = "allow"