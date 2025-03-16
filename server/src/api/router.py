from fastapi import APIRouter, WebSocket, WebSocketDisconnect, Depends, HTTPException, Query, Path
from fastapi.responses import JSONResponse
import json
import asyncio
from datetime import datetime
from typing import List
from src.models.chat import (
    ChatRequest, ChatMessage, ChatHistory, 
    SaveChatRequest, ChatListResponse, ChatResponse
)
from src.utils.gemini_client import GeminiClient
from src.utils.database import save_chat, update_chat, get_chat, list_chats, delete_chat

router = APIRouter()
gemini_client = GeminiClient()

async def _generate_and_send_title_recommendation(websocket: WebSocket, 
                                                history: ChatHistory, 
                                                chat_id: int, 
                                                user_secret: str):
    """Generate a title recommendation and send it to the client and auto-update the database."""
    try:
        # Generate title recommendation
        recommended_title = await gemini_client.generate_chat_title(history)
        
        print(f"\n=== SENDING TITLE RECOMMENDATION ===")
        print(f"Chat ID: {chat_id}")
        print(f"Recommended Title: {recommended_title}")
        print(f"Time: {datetime.utcnow().isoformat()}")
        print(f"===================================\n")
        
        # IMPORTANT: First update the title in the database automatically
        # This ensures the title is updated even if the client doesn't handle it
        print(f"\n=== AUTO-UPDATING TITLE IN DATABASE ===")
        print(f"Chat ID: {chat_id}")
        print(f"New Title: {recommended_title}")
        
        # Get the current chat to keep content intact
        current_chat = await get_chat(chat_id, user_secret)
        if current_chat:
            # Update the title
            success = await update_chat(
                chat_id,
                user_secret,
                title=recommended_title,
                chat_content=current_chat["messages"]
            )
            
            print(f"Auto-update success: {success is not None}")
            
            # Now send the recommendation to the client
            await websocket.send_text(json.dumps({
                "status": "title_recommendation",
                "chat_id": chat_id,
                "recommended_title": recommended_title,
                "title_updated": True,  # Inform client that title has already been saved
                "updated_at": success
            }, ensure_ascii=False))
        else:
            print(f"Could not auto-update title - chat not found: {chat_id}")
            # Just send the recommendation to the client without updating
            await websocket.send_text(json.dumps({
                "status": "title_recommendation",
                "chat_id": chat_id,
                "recommended_title": recommended_title,
                "title_updated": False
            }, ensure_ascii=False))
        
    except Exception as e:
        print(f"Error generating/saving title recommendation: {e}")
        import traceback
        print(traceback.format_exc())
        # We don't send the error to the client as this is a background task

# The REST API endpoint for chat completions has been removed since the Flutter app only uses WebSockets.

@router.websocket("/api/chat/completion/stream")
async def chat_completion_stream(websocket: WebSocket):
    """Stream chat completions via WebSocket."""
    await websocket.accept()
    full_response = ""
    
    try:
        while True:
            # Receive and parse JSON message
            data = await websocket.receive_text()
            request_data = json.loads(data, strict=False)
            
            # Check if it's a special command
            if "command" in request_data:
                if request_data["command"] == "save_chat":
                    try:
                        command_data = request_data["data"]
                        user_secret = command_data.get("user_secret")
                        title = command_data.get("title")
                        history_data = command_data.get("history")
                        
                        if not user_secret or not title or not history_data:
                            await websocket.send_text(json.dumps({
                                "status": "error",
                                "message": "Missing required fields for saving chat"
                            }, ensure_ascii=False))
                            continue
                        
                        # Convert history_data to ChatHistory model
                        messages = []
                        now_base = datetime.utcnow().timestamp()
                        for i, msg in enumerate(history_data.get("messages", [])):
                            # Add timestamp if not present
                            if "timestamp" not in msg:
                                msg["timestamp"] = datetime.fromtimestamp(now_base + (i * 0.001)).isoformat()
                            messages.append(ChatMessage(**msg))
                        
                        history = ChatHistory(
                            messages=messages
                        )
                        
                        chat_id = command_data.get("chat_id")
                        
                        if chat_id:
                            # Update existing chat
                            assistant_messages = [msg for msg in messages if msg.role == "assistant"]
                            if assistant_messages:
                                success = await update_chat(
                                    chat_id,
                                    user_secret,
                                    title=title,
                                    chat_content=messages
                                )
                                if success:
                                    # Notify clients that a chat was updated
                                    update_msg = {
                                        "status": "saved",
                                        "id": chat_id,
                                        "title": title,
                                        "updated_at": success
                                    }
                                    await websocket.send_text(json.dumps(update_msg, ensure_ascii=False))
                                else:
                                    await websocket.send_text(json.dumps({
                                        "status": "error",
                                        "message": "Failed to update chat"
                                    }, ensure_ascii=False))
                        else:
                            # Create new chat - always use our default system message
                            now_system = datetime.utcnow().isoformat()
                            messages.insert(0, ChatMessage(
                                role="system", 
                                content=gemini_client.default_system_message,
                                timestamp=now_system
                            ))
                                
                            new_chat_id = await save_chat(
                                user_secret,
                                title,
                                messages
                            )
                            
                            await websocket.send_text(json.dumps({
                                "status": "saved",
                                "id": new_chat_id,
                                "title": title
                            }, ensure_ascii=False))
                    except Exception as e:
                        import traceback
                        error_traceback = traceback.format_exc()
                        print("\n\n=== SERVER EXCEPTION ===")
                        print(error_traceback)
                        print("========================\n\n")
                        
                        await websocket.send_text(json.dumps({
                            "status": "error",
                            "message": str(e)
                        }))
                elif request_data["command"] == "update_title":
                    try:
                        command_data = request_data["data"]
                        user_secret = command_data.get("user_secret")
                        title = command_data.get("title")
                        chat_id = command_data.get("chat_id")
                        
                        print(f"\n=== RECEIVED TITLE UPDATE REQUEST ===")
                        print(f"Chat ID: {chat_id}")
                        print(f"New Title: {title}")
                        print(f"Time: {datetime.utcnow().isoformat()}")
                        print(f"Raw data: {command_data}")
                        print(f"=====================================\n")
                        
                        if not user_secret or not title or not chat_id:
                            await websocket.send_text(json.dumps({
                                "status": "error",
                                "message": "Missing required fields for updating title"
                            }))
                            continue
                        
                        # Get the current chat to keep content intact
                        current_chat = await get_chat(chat_id, user_secret)
                        if not current_chat:
                            await websocket.send_text(json.dumps({
                                "status": "error",
                                "message": "Chat not found"
                            }))
                            continue
                        
                        print(f"\n=== UPDATING CHAT TITLE IN DATABASE ===")
                        print(f"Chat ID: {chat_id}")
                        print(f"Current title in DB: {current_chat['title']}")
                        print(f"New title to save: {title}")
                        print(f"Message count: {len(current_chat['messages'])}")
                        print(f"=====================================\n")
                        
                        # Update the title
                        success = await update_chat(
                            chat_id,
                            user_secret,
                            title=title,
                            chat_content=current_chat["messages"]
                        )
                        
                        if success:
                            # Verify title was updated in database
                            updated_chat = await get_chat(chat_id, user_secret)
                            print(f"\n=== TITLE UPDATE VERIFICATION ===")
                            print(f"Chat ID: {chat_id}")
                            print(f"Title after update: {updated_chat['title']}")
                            print(f"Expected title: {title}")
                            print(f"Match: {updated_chat['title'] == title}")
                            print(f"=====================================\n")
                            
                            # Notify client that title was updated - use a broadcast-like message
                            # to ensure all clients are informed about the title change
                            update_msg = {
                                "status": "title_updated",
                                "id": chat_id,
                                "title": title,
                                "updated_at": success
                            }
                            await websocket.send_text(json.dumps(update_msg))
                            print(f"Title update notification sent to client: {update_msg}")
                        else:
                            print(f"\n=== TITLE UPDATE FAILED ===")
                            print(f"Chat ID: {chat_id}")
                            print(f"=====================================\n")
                            
                            await websocket.send_text(json.dumps({
                                "status": "error",
                                "message": "Failed to update chat title"
                            }))
                            
                    except Exception as e:
                        import traceback
                        error_traceback = traceback.format_exc()
                        print("\n\n=== SERVER EXCEPTION ===")
                        print(error_traceback)
                        print("========================\n\n")
                        
                        await websocket.send_text(json.dumps({
                            "status": "error",
                            "message": str(e)
                        }))
                continue
            
            try:
                # Parse request using Pydantic
                request = ChatRequest(**request_data)
                
                # Convert messages to Gemini format
                gemini_messages = []
                for msg in request.history.messages:
                    if msg.role == "user":
                        gemini_messages.append({
                            "role": "user",
                            "parts": [{"text": msg.content}]
                        })
                    elif msg.role == "assistant":
                        gemini_messages.append({
                            "role": "model", 
                            "parts": [{"text": msg.content}]
                        })
                
                # Always use our default system message from the server
                
                print("\n=== PROCESSING CHAT COMPLETION REQUEST ===")
                print(f"Temperature: {request.temperature}")
                print(f"Top_p: {request.top_p}")
                print(f"Top_k: {request.top_k}")
                print(f"Max tokens: {request.max_tokens}")
                print(f"Chat ID: {request.chat_id}")
                print("========================================\n")
                
                # Stream the response
                # Log full request info before streaming
                print("\n=== STREAMING REQUEST INFO ===")
                print(f"Request temperature: {request.temperature}")
                print(f"Request top_p: {request.top_p}")
                print(f"Request top_k: {request.top_k}")
                print(f"Request max_tokens: {request.max_tokens}")
                print(f"Request message count: {len(request.history.messages)}")
                
                # Log all messages in the request to debug truncation
                print("\n--- REQUEST MESSAGES ---")
                for i, msg in enumerate(request.history.messages):
                    print(f"[{i}] {msg.role}: {msg.content}")
                print("------------------------\n")
                
                async for chunk in gemini_client.generate_completion_stream(
                    history=request.history,
                    temperature=request.temperature,
                    top_p=request.top_p,
                    top_k=request.top_k,
                    max_tokens=request.max_tokens
                ):
                    full_response += chunk
                    
                    # Check if chunk is too large and log message
                    chunk_size = len(chunk)
                    if chunk_size > 2000:
                        print(f"WARNING: Large chunk size: {chunk_size} bytes")
                        
                    # Ensure proper UTF-8 encoding and send to client
                    await websocket.send_text(json.dumps({
                        "chunk": chunk,
                        "status": "streaming"
                    }, ensure_ascii=False))
                
                # Save or update chat if user_secret is provided
                saved_chat_id = None
                title = request.title
                if request.user_secret and full_response:
                    if request.chat_id:
                        # Update existing chat with complete message history
                        history = request.history
                        messages = history.messages.copy()
                        now = datetime.utcnow().isoformat()
                        messages.append(ChatMessage(
                            role="assistant", 
                            content=full_response,
                            timestamp=now
                        ))
                        
                        # Always use the default system message from GeminiClient
                        now_system = datetime.utcnow().isoformat()
                        messages.insert(0, ChatMessage(
                            role="system", 
                            content=gemini_client.default_system_message,
                            timestamp=now_system
                        ))
                            
                        success = await update_chat(
                            request.chat_id, 
                            request.user_secret, 
                            title=title, 
                            chat_content=messages
                        )
                        if success:
                            saved_chat_id = request.chat_id
                    elif title:
                        # Create new chat
                        history = request.history
                        messages = history.messages.copy()
                        now = datetime.utcnow().isoformat()
                        messages.append(ChatMessage(
                            role="assistant", 
                            content=full_response,
                            timestamp=now
                        ))
                        
                        # Always use the default system message from GeminiClient
                        now_system = datetime.utcnow().isoformat()
                        messages.insert(0, ChatMessage(
                            role="system", 
                            content=gemini_client.default_system_message,
                            timestamp=now_system
                        ))
                            
                        saved_chat_id = await save_chat(
                            request.user_secret,
                            title,
                            messages
                        )
                        
                    # Start a task to generate a title recommendation for the first 3 messages
                    # without blocking the response
                    # Create a new history object with the same data
                    history_with_response = ChatHistory(
                        messages=request.history.messages.copy()
                    )
                    now_resp = datetime.utcnow().isoformat()
                    history_with_response.messages.append(ChatMessage(
                        role="assistant", 
                        content=full_response,
                        timestamp=now_resp
                    ))
                    
                    # Only generate title for the first three user inputs
                    user_message_count = sum(1 for msg in history_with_response.messages if msg.role == "user")
                    if user_message_count <= 3 and saved_chat_id:
                        # Create a task to generate title in background
                        asyncio.create_task(_generate_and_send_title_recommendation(
                            websocket,
                            history_with_response,
                            saved_chat_id,
                            request.user_secret
                        ))
                
                # Send completion message
                completion_response = {
                    "status": "complete"
                }
                
                # Include the chat ID if available
                if saved_chat_id:
                    completion_response["id"] = saved_chat_id
                
                # Log the completion status and full response
                print("\n=== CHAT COMPLETION FINISHED ===")
                print(f"Full response length: {len(full_response)} characters")
                print(f"Chat ID: {saved_chat_id}")
                print(f"Time: {datetime.utcnow().isoformat()}")
                
                # Prepare messages for logging
                history = request.history
                messages = history.messages.copy()
                messages.append(ChatMessage(role="assistant", content=full_response))
        
                # Note: System messages are handled by the server and never included in client messages
                
                print("\n--- Full Chat Content (without system messages) ---")
                print(f"Total messages: {len(messages) - (1 if any(msg.role == 'system' for msg in messages) else 0)}")
                
                # Print full messages without truncation
                for i, msg in enumerate(messages):
                    # Skip system messages in logs
                    if msg.role == "system":
                        print(f"[{i}] (system message - not shown in logs or client)")
                        continue
                    
                    # Print full message content - no truncation
                    print(f"[{i}] {msg.role}:")
                    print(f"--- BEGIN CONTENT ---")
                    print(msg.content)
                    print(f"--- END CONTENT ---")
                
                # Create a serializable version of all messages for JSON dumping,
                # but NEVER include system messages in logs or client traffic
                serializable_messages = []
                for msg in messages:
                    # Skip system messages - never expose them to clients
                    if msg.role == "system":
                        continue
                        
                    serializable_messages.append({
                        "role": msg.role,
                        "content": msg.content,
                        "timestamp": getattr(msg, "timestamp", None)
                    })
                
                # Dump the entire conversation as JSON for debugging
                try:
                    conversation_json = {
                        "chat_id": saved_chat_id,
                        "title": request.title or "Untitled Chat",
                        "messages": serializable_messages
                    }
                    # Save to variable first to avoid truncation
                    json_response = json.dumps(conversation_json, ensure_ascii=False)
                    
                    print("\nFULL CONVERSATION JSON START >>>")
                    # Also save to a file for complete debugging
                    with open("/tmp/debug_websocket_response.json", "w") as f:
                        f.write(json_response)
                    print(f"Full WebSocket response written to /tmp/debug_websocket_response.json (length: {len(json_response)})")
                    # Print to console
                    print(json_response)
                    print("<<< FULL CONVERSATION JSON END")
                except Exception as e:
                    print(f"Error serializing conversation for logging: {e}")
                    
                print("--------------------------------")
                
                print("================================\n")
                
                await websocket.send_text(json.dumps(completion_response, ensure_ascii=False))
                
                # Reset response for next message
                full_response = ""
                
            except Exception as e:
                import traceback
                error_traceback = traceback.format_exc()
                print("\n\n=== SERVER EXCEPTION ===")
                print(error_traceback)
                print("========================\n\n")
                
                await websocket.send_text(json.dumps({
                    "status": "error",
                    "message": str(e)
                }, ensure_ascii=False))
                
    except WebSocketDisconnect:
        # Client disconnected
        pass

@router.post("/api/chats", status_code=201)
async def create_chat(request: SaveChatRequest):
    """Save a new chat."""
    try:
        history = request.history
        messages = history.messages.copy()
        
        # Add timestamps to messages if not present
        now_base = datetime.utcnow().timestamp()
        for i, msg in enumerate(messages):
            if not getattr(msg, "timestamp", None):
                setattr(msg, "timestamp", datetime.fromtimestamp(now_base + (i * 0.001)).isoformat())
        
        # Always use the default system message from GeminiClient - client cannot override this
        now_system = datetime.utcnow().isoformat()
        messages.insert(0, ChatMessage(
            role="system", 
            content=gemini_client.default_system_message,
            timestamp=now_system
        ))
            
        chat_id = await save_chat(
            request.user_secret,
            request.title,
            messages
        )
        
        return {
            "id": chat_id,
            "title": request.title,
            "status": "success"
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@router.get("/api/chats", response_model=List[ChatListResponse])
async def get_chats(user_secret: str = Query(..., description="User secret key")):
    """List all chats for a user."""
    try:
        print(f"\n=== API CALL: List All Chats ===")
        print(f"User secret: {user_secret}")
        print(f"Time: {datetime.utcnow().isoformat()}")
        print(f"================================\n")
        
        chats = await list_chats(user_secret)
        
        print(f"\n=== API RESPONSE: Chats List ===")
        print(f"Returning {len(chats)} chats to client")
        for chat in chats:
            print(f"Chat ID: {chat['id']}, Title: {chat['title']}")
        print(f"=================================\n")
        
        return chats
    except Exception as e:
        print(f"Error listing chats: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@router.get("/api/chats/{chat_id}", response_model=ChatResponse)
async def get_chat_by_id(
    chat_id: int = Path(..., description="Chat ID"), 
    user_secret: str = Query(..., description="User secret key")
):
    """Retrieve a specific chat."""
    try:
        print(f"\n=== API CALL: Get Chat By ID ===")
        print(f"Chat ID: {chat_id}")
        print(f"User secret: {user_secret}")
        print(f"Time: {datetime.utcnow().isoformat()}")
        print(f"================================\n")
        
        chat = await get_chat(chat_id, user_secret)
        if not chat:
            raise HTTPException(status_code=404, detail="Chat not found")
        
        # Add detailed logging of chat content before returning to client
        print("\n=== CHAT CONTENT (API RESPONSE) ===")
        print(f"Chat ID: {chat['id']}")
        print(f"Title: {chat['title']}")
        print(f"Total non-system messages: {len(chat['messages'])}")
        
        # Print all message content without truncation
        for i, msg in enumerate(chat['messages']):
            print(f"[{i}] {msg.role}:")
            print(f"--- BEGIN CONTENT ---")
            print(msg.content)
            print(f"--- END CONTENT ---")
        
        # Dump the entire response JSON for debugging
        try:
            # Create a serializable version of the chat object, but NEVER include system messages
            serializable_chat = {
                "id": chat["id"],
                "title": chat["title"],
                "messages": [
                    {
                        "role": msg.role,
                        "content": msg.content,
                        "timestamp": getattr(msg, "timestamp", None)
                    } 
                    for msg in chat["messages"] 
                    if msg.role != "system"  # Never expose system messages to client
                ],
                "created_at": chat["created_at"],
                "updated_at": chat["updated_at"]
            }
            
            # Save to a variable first to avoid truncation in print statements
            json_response = json.dumps(serializable_chat, ensure_ascii=False)
            
            print("\nFULL JSON RESPONSE START >>>")
            # Also save to a file for complete debugging
            with open("/tmp/debug_api_response.json", "w") as f:
                f.write(json_response)
            print(f"Full API response written to /tmp/debug_api_response.json (length: {len(json_response)})")
            # Print to console 
            print(json_response)
            print("<<< FULL JSON RESPONSE END")
        except Exception as e:
            print(f"Error serializing chat for logging: {e}")
        
        print("=====================================\n")
        
        return chat
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@router.delete("/api/chats/{chat_id}", status_code=204)
async def delete_chat_by_id(
    chat_id: int = Path(..., description="Chat ID"), 
    user_secret: str = Query(..., description="User secret key")
):
    """Delete a specific chat."""
    try:
        success = await delete_chat(chat_id, user_secret)
        if not success:
            raise HTTPException(status_code=404, detail="Chat not found")
        return None
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
        
@router.put("/api/chats/{chat_id}/title", status_code=200)
async def update_chat_title(
    chat_id: int = Path(..., description="Chat ID"),
    user_secret: str = Query(..., description="User secret key"),
    title: str = Query(..., description="New chat title")
):
    """Update a chat title."""
    try:
        print(f"\n=== REST API TITLE UPDATE REQUEST ===")
        print(f"Chat ID: {chat_id}")
        print(f"New Title: {title}")
        print(f"Time: {datetime.utcnow().isoformat()}")
        print(f"=====================================\n")
        
        # Get the current chat to keep content intact
        current_chat = await get_chat(chat_id, user_secret)
        if not current_chat:
            print(f"Chat not found: {chat_id}")
            raise HTTPException(status_code=404, detail="Chat not found")
            
        print(f"\n=== UPDATING CHAT TITLE IN DATABASE (REST) ===")
        print(f"Chat ID: {chat_id}")
        print(f"Current title in DB: {current_chat['title']}")
        print(f"New title to save: {title}")
        print(f"Message count: {len(current_chat['messages'])}")
        print(f"=====================================\n")
            
        # Update the title while preserving content
        success = await update_chat(
            chat_id, 
            user_secret, 
            title=title, 
            chat_content=current_chat["messages"]
        )
        
        if not success:
            print(f"Title update failed: {chat_id}")
            raise HTTPException(status_code=404, detail="Chat not found")
            
        # Verify title update
        updated_chat = await get_chat(chat_id, user_secret)
        print(f"\n=== TITLE UPDATE VERIFICATION (REST) ===")
        print(f"Chat ID: {chat_id}")
        print(f"Title after update: {updated_chat['title']}")
        print(f"Expected title: {title}")
        print(f"Match: {updated_chat['title'] == title}")
        print(f"=====================================\n")
            
        return {
            "status": "success", 
            "id": chat_id, 
            "title": title, 
            "updated_at": success
        }
    except Exception as e:
        print(f"Error updating title: {e}")
        raise HTTPException(status_code=500, detail=str(e))
