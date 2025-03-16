#!/usr/bin/env python3
import asyncio
import json
import os
import websockets
import sys
import pathlib

# Add parent directory to Python path to find the src module
sys.path.insert(0, str(pathlib.Path(__file__).parent.parent))
from src.models.chat import ChatMessage, ChatHistory, ChatRequest

async def test_chat():
    """Test the chat API by simulating a conversation."""
    uri = "ws://localhost:8035/api/chat/completion/stream"
    
    async with websockets.connect(uri) as websocket:
        # First message: "hello"
        history = ChatHistory(
            system_message="You are a helpful AI assistant.",
            messages=[
                ChatMessage(role="user", content="hello")
            ]
        )
        
        request = ChatRequest(history=history)
        
        # Send the request
        await websocket.send(json.dumps(request.model_dump()))
        
        # Collect and print the response
        full_response = ""
        while True:
            response = await websocket.recv()
            data = json.loads(response)
            
            if data["status"] == "streaming":
                chunk = data["chunk"]
                full_response += chunk
                print(chunk, end="", flush=True)
            elif data["status"] == "complete":
                print("\n\nFirst response complete!\n")
                break
            elif data["status"] == "error":
                print(f"\nError: {data['message']}")
                break
        
        # Add the assistant's response to history
        history.messages.append(ChatMessage(role="assistant", content=full_response))
        
        # Add second user message: "how are you"
        history.messages.append(ChatMessage(role="user", content="how are you"))
        
        # Create and send the second request
        second_request = ChatRequest(history=history)
        await websocket.send(json.dumps(second_request.model_dump()))
        
        # Collect and print the second response
        second_response = ""
        while True:
            response = await websocket.recv()
            data = json.loads(response)
            
            if data["status"] == "streaming":
                chunk = data["chunk"]
                second_response += chunk
                print(chunk, end="", flush=True)
            elif data["status"] == "complete":
                print("\n\nSecond response complete!")
                break
            elif data["status"] == "error":
                print(f"\nError: {data['message']}")
                break

if __name__ == "__main__":
    # Note: GEMINI_API_KEY is only required on the server side now
    pass
        
    # Run the test
    asyncio.run(test_chat())
