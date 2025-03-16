import os
import asyncio
import json
from typing import List, Dict, Any, AsyncGenerator
from google import genai
from google.genai import types
from src.models.chat import ChatHistory, ChatMessage

class GeminiClient:
    def __init__(self):
        api_key = os.environ.get("GEMINI_API_KEY")
        if not api_key:
            raise ValueError("GEMINI_API_KEY environment variable is not set")
        
        self.client = genai.Client(api_key=api_key)
        self.model_name = "learnlm-1.5-pro-experimental"
        
        # Fixed system message for learning assistant
        self.default_system_message = """Ты - отличный учитель для детей и взрослых. Их язык - русский. Используй только их язык. Всегда избегай прямых решений поставленных тебе задач, если такая задача тебе поступит, то поговори с учеником, что именно ему непонятно, а если он не сможет объяснить, то твоя задача выяснить его слабые стороны встречными более простыми задачами и когда он научится их решать, то можно постепенно вернуться и к задачам уровня первоначальной непонятной задачи. Когда ученик сможет решить эту сложную задачу, следует предложить решить ему самостоятельно исходное задание, потому что теперь он умеет решать задания такого типа. Пожалуйста будь отличным учителем. Старайся противодействовать использованию тебя как инструмента для решения домашних заданий ученика. Избегай отвечать на вопросы типа "а правильно будет если первым действием я выполню ..... ", потому что таким образом ученик просто использует тебя как детектор истины, и просто перебором вариантов и использованием тебя, решит свою задачу. Если ты видишь такое использование, отказывайся отвечать и вместо этого предлагай ученику научиться решать более простые задачи"""
    
    def _create_config(self, 
                      temperature: float = 1.0,
                      top_p: float = 0.95,
                      top_k: int = 64,
                      max_tokens: int = 8192,
                      system_instruction: str = "") -> types.GenerateContentConfig:
        """Create a generation config."""
        # If no specific system instruction is provided, use the default
        if not system_instruction:
            system_instruction = self.default_system_message
            
        return types.GenerateContentConfig(
            temperature=temperature,
            top_p=top_p,
            top_k=top_k,
            max_output_tokens=max_tokens,
            system_instruction=system_instruction
        )
    
    # The _prepare_chat_history method has been removed since we directly create
    # Gemini-formatted messages in the generate_completion_stream method
    
    # The generate_completion method has been removed since it's not used by the Flutter app.
    # Only the WebSocket-based streaming completion is used.
    
    async def generate_completion_stream(self, 
                                       history: ChatHistory,
                                       temperature: float = 1.0,
                                       top_p: float = 0.95,
                                       top_k: int = 64,
                                       max_tokens: int = 8192) -> AsyncGenerator[str, None]:
        """Generate a completion with streaming response."""
        
        # Log the entire chat history without truncation
        print("\n=== CHAT HISTORY (WEBSOCKET) ===")
        print(f"System Message: {self.default_system_message}")
        for i, msg in enumerate(history.messages):
            print(f"[{i}] {msg.role}:")
            print(f"--- BEGIN FULL CONTENT ---")
            print(msg.content)
            print(f"--- END FULL CONTENT ---")
        print("================================\n")
        
        # Extract the last user message which is the prompt
        last_user_message = None
        for msg in reversed(history.messages):
            if msg.role == "user":
                last_user_message = msg.content
                print("\n=== NEW USER MESSAGE (WEBSOCKET) ===")
                print(f"User query length: {len(msg.content)} characters")
                print("--- BEGIN FULL USER QUERY ---")
                print(last_user_message)
                print("--- END FULL USER QUERY ---")
                print("================================\n")
                break
        
        if not last_user_message:
            raise ValueError("No user message found in history")
            
        # Convert to Gemini's required format
        gemini_messages = []
        for msg in history.messages:
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
        
        print(f"Total messages in Gemini format: {len(gemini_messages)}")
        print("===========================================\n")
        
        # Set up config with system message
        config = self._create_config(
            temperature=temperature,
            top_p=top_p,
            top_k=top_k,
            max_tokens=max_tokens,
            system_instruction=self.default_system_message
        )
            
        # Call Gemini with properly formatted messages
        # For completeness, let's log the entire history to debug file
        with open("/tmp/debug_gemini_history.json", "w") as f:
            json_history = json.dumps(gemini_messages, ensure_ascii=False, indent=2)
            f.write(json_history)
            print(f"Full Gemini message history written to /tmp/debug_gemini_history.json")
                
        # Always use the content-generation stream
        stream = await asyncio.to_thread(
            self.client.models.generate_content_stream,
            model=self.model_name,
            contents=gemini_messages,
            config=config
        )
        
        # Add chunk counting and detailed logging
        chunk_count = 0
        for chunk in stream:
            if chunk.text:
                # Log each chunk for debugging truncation
                chunk_count += 1
                chunk_text = chunk.text
                chunk_len = len(chunk_text)
                
                print(f"\n=== STREAM CHUNK #{chunk_count} ===")
                print(f"Chunk length: {chunk_len} characters")
                if chunk_len < 100:
                    # If chunk is small, show it entirely
                    print(f"Full chunk: {chunk_text}")
                else:
                    # Otherwise show beginning and end to save space
                    print(f"Chunk start: {chunk_text[:50]}...")
                    print(f"Chunk end: ...{chunk_text[-50:]}")
                    
                    # Also save long chunks to disk for debugging
                    if chunk_len > 1000:
                        with open(f"/tmp/debug_chunk_{chunk_count}.txt", "w") as f:
                            f.write(chunk_text)
                        print(f"Full chunk saved to /tmp/debug_chunk_{chunk_count}.txt")
                
                print("===================\n")
                
                yield chunk_text
                    
    async def generate_chat_title(self, history: ChatHistory) -> str:
        """Generate a title recommendation for a chat based on its content."""
        
        # Create a prompt for getting a title recommendation
        title_prompt = """Based on the conversation above, create a short, descriptive title for this chat.
The title should be a single line, no more than 50 characters, and should capture the main topic or purpose of the conversation.
Return ONLY the title text with no prefixes, quotes, or additional formatting."""
        
        # Convert messages to Gemini format
        gemini_messages = []
        
        # Add conversation messages in proper format
        for msg in history.messages:
            if msg.role == "user":
                gemini_messages.append({
                    "role": "user", 
                    "parts": [msg.content]
                })
            elif msg.role == "assistant":
                gemini_messages.append({
                    "role": "model", 
                    "parts": [msg.content]
                })
        
        # Add final user message with the title prompt
        gemini_messages.append({
            "role": "user",
            "parts": [title_prompt]
        })
        
        # Log history for debugging
        print(f"\n=== GENERATING TITLE WITH {len(gemini_messages)} MESSAGES ===")
        with open("/tmp/debug_title_history.json", "w") as f:
            json_history = json.dumps(gemini_messages, ensure_ascii=False, indent=2)
            f.write(json_history)
            print(f"Title generation history written to /tmp/debug_title_history.json")
        
        # Generate title
        config = self._create_config(
            temperature=0.7,  # Lower temperature for more focused output
            top_p=0.95,
            top_k=64,
            max_tokens=100,  # Short output for titles
            system_instruction="You are a helpful assistant that creates concise, relevant titles."
        )
        
        response = await asyncio.to_thread(
            self.client.models.generate_content,
            model=self.model_name,
            contents=gemini_messages,
            config=config
        )
        
        # Clean and validate the title
        title = response.text.strip()
        
        # Ensure it's a single line
        title = title.split('\n')[0]
        
        # Truncate if too long
        if len(title) > 50:
            title = title[:47] + "..."
            
        return title
