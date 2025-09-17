import os
import aiosqlite
import json
from datetime import datetime
from src.models.chat import ChatMessage

DATABASE_PATH = os.environ.get("DATABASE_PATH", "chats.db")


def set_database_path(path: str | None) -> None:
    """Override database file path at runtime."""
    global DATABASE_PATH
    if path:
        DATABASE_PATH = path


def ensure_database_dir() -> None:
    directory = os.path.dirname(os.path.abspath(DATABASE_PATH))
    if directory:
        os.makedirs(directory, exist_ok=True)

async def init_db():
    """Initialize the database with required tables."""
    ensure_database_dir()
    # Ensure proper handling of Unicode characters in SQLite
    async with aiosqlite.connect(DATABASE_PATH) as db:
        await db.execute("PRAGMA encoding='UTF-8';")  # Ensure UTF-8 encoding
        await db.execute('''
        CREATE TABLE IF NOT EXISTS chats (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_secret TEXT NOT NULL,
            title TEXT NOT NULL,
            content TEXT NOT NULL,
            created_at TIMESTAMP NOT NULL,
            updated_at TIMESTAMP NOT NULL
        )
        ''')
        
        await db.commit()

async def save_chat(user_secret: str, title: str, chat_content):
    """Save a new chat with full content as JSON."""
    now = datetime.utcnow().isoformat()
    
    print(f"\n=== CREATING NEW CHAT ===")
    print(f"Title: {title}")
    print(f"Time: {now}")
    print(f"===========================\n")
    
    # Convert messages to serializable format, assuming timestamps are already present
    serialized_content = []
    for msg in chat_content:
        # Ensure timestamp exists, default to 'now' only if absolutely necessary (should not happen ideally)
        msg_timestamp = getattr(msg, 'timestamp', None) or now 
            
        serialized_content.append({
            "role": msg.role,
            "content": msg.content,
            "timestamp": msg_timestamp
        })
    
    # Convert to JSON string with proper Unicode support for Russian text
    content_json = json.dumps(serialized_content, ensure_ascii=False)
    
    async with aiosqlite.connect(DATABASE_PATH) as db:
        # Insert chat with full content
        cursor = await db.execute(
            "INSERT INTO chats (user_secret, title, content, created_at, updated_at) VALUES (?, ?, ?, ?, ?)",
            (user_secret, title, content_json, now, now)
        )
        chat_id = cursor.lastrowid
        print(f"Chat created with ID: {chat_id}")
        
        await db.commit()
        return chat_id

async def update_chat(chat_id: int, user_secret: str, title: str = None, chat_content = None):
    """Update an existing chat with new content and/or title."""
    now = datetime.utcnow().isoformat()
    
    # Extra logging to debug title update issues
    print(f"\n=== UPDATE_CHAT FUNCTION CALLED ===")
    print(f"Chat ID: {chat_id}")
    print(f"Title provided: {title}")
    print(f"Content provided: {'Yes' if chat_content else 'No'}")
    print(f"Time: {now}")
    print(f"===================================\n")
    
    async with aiosqlite.connect(DATABASE_PATH) as db:
        # Verify the chat belongs to the user and get current values
        cursor = await db.execute(
            "SELECT id, title FROM chats WHERE id = ? AND user_secret = ?",
            (chat_id, user_secret)
        )
        chat = await cursor.fetchone()
        
        if not chat:
            print(f"Chat not found in database: {chat_id}")
            return None
            
        print(f"Current title in DB: {chat[1]}")
        
        # Update title and/or content if provided
        if title and chat_content:
            print(f"\n=== UPDATING CHAT TITLE AND CONTENT ===")
            print(f"Chat ID: {chat_id}")
            print(f"New Title: {title}")
            print(f"Time: {now}")
            print(f"===========================\n")
            
            # Convert messages to serializable format, assuming timestamps are already present
            serialized_content = []
            for msg in chat_content:
                # Ensure timestamp exists, default to 'now' only if absolutely necessary
                msg_timestamp = getattr(msg, 'timestamp', None) or now
                    
                serialized_content.append({
                    "role": msg.role,
                    "content": msg.content,
                    "timestamp": msg_timestamp
                })
            
            content_json = json.dumps(serialized_content)
            await db.execute(
                "UPDATE chats SET title = ?, content = ?, updated_at = ? WHERE id = ?",
                (title, content_json, now, chat_id)
            )
            
            # Verify update
            cursor = await db.execute(
                "SELECT title FROM chats WHERE id = ?",
                (chat_id,)
            )
            updated_title = await cursor.fetchone()
            print(f"After update query, title is now: {updated_title[0]}")
        elif title:
            print(f"\n=== UPDATING CHAT TITLE ===")
            print(f"Chat ID: {chat_id}")
            print(f"New Title: {title}")
            print(f"Time: {now}")
            print(f"===========================\n")
            
            await db.execute(
                "UPDATE chats SET title = ?, updated_at = ? WHERE id = ?",
                (title, now, chat_id)
            )
            
            # Verify update
            cursor = await db.execute(
                "SELECT title FROM chats WHERE id = ?",
                (chat_id,)
            )
            updated_title = await cursor.fetchone()
            print(f"After update query, title is now: {updated_title[0]}")
        elif chat_content:
            print(f"\n=== UPDATING CHAT CONTENT ===")
            print(f"Chat ID: {chat_id}")
            print(f"Time: {now}")
            print(f"===========================\n")
            
            # Convert messages to serializable format, assuming timestamps are already present
            serialized_content = []
            for msg in chat_content:
                 # Ensure timestamp exists, default to 'now' only if absolutely necessary
                msg_timestamp = getattr(msg, 'timestamp', None) or now
                    
                serialized_content.append({
                    "role": msg.role,
                    "content": msg.content,
                    "timestamp": msg_timestamp
                })
            
            content_json = json.dumps(serialized_content)
            await db.execute(
                "UPDATE chats SET content = ?, updated_at = ? WHERE id = ?",
                (content_json, now, chat_id)
            )
        else:
            await db.execute(
                "UPDATE chats SET updated_at = ? WHERE id = ?",
                (now, chat_id)
            )
        
        # Final commit
        await db.commit()
        
        # Final verification after commit
        cursor = await db.execute(
            "SELECT title FROM chats WHERE id = ?",
            (chat_id,)
        )
        final_title = await cursor.fetchone()
        print(f"FINAL VERIFICATION - title in DB after commit: {final_title[0]}")
        
        return now  # Return the updated timestamp

async def get_chat(chat_id: int, user_secret: str):
    """Retrieve a chat by ID for a specific user."""
    async with aiosqlite.connect(DATABASE_PATH) as db:
        await db.execute("PRAGMA encoding='UTF-8';")  # Ensure UTF-8 encoding
        # Get chat metadata and content
        cursor = await db.execute(
            "SELECT id, title, content, created_at, updated_at FROM chats WHERE id = ? AND user_secret = ?",
            (chat_id, user_secret)
        )
        chat = await cursor.fetchone()
        
        if not chat:
            return None
        
        print(f"\n=== RETRIEVING CHAT FROM DB ===")
        print(f"Chat ID: {chat[0]}")
        print(f"Title from DB: {chat[1]}")
        print(f"Created at: {chat[3]}")
        print(f"Updated at: {chat[4]}")
        print(f"=================================\n")
        
        # Parse the JSON content with proper Unicode handling for Russian text
        message_data = json.loads(chat[2], strict=False)
        
        # Sort messages by timestamp if available
        message_data = sorted(message_data, key=lambda x: x.get('timestamp', '0'))
        
        # Convert back to ChatMessage objects with timestamps
        messages = []
        for msg_data in message_data:
            # Skip system messages when sending to client
            if msg_data.get("role") == "system":
                # System message should not be exposed to client, only for internal use
                continue
                
            # Create a ChatMessage with timestamp if it exists
            timestamp = msg_data.get("timestamp")
            chat_msg = ChatMessage(
                role=msg_data["role"],
                content=msg_data["content"]
            )
            # Add timestamp as an attribute if it exists
            if timestamp:
                chat_msg.timestamp = timestamp
            messages.append(chat_msg)
        
        # Add detailed logging of chat content before returning
        print("\n=== CHAT CONTENT (BEFORE RETURNING TO CLIENT) ===")
        print(f"Chat ID: {chat[0]}")
        print(f"Total non-system messages: {len(messages)}")
        
        # Print all message content without truncation
        for i, msg in enumerate(messages):
            print(f"[{i}] {msg.role}:")
            print(f"--- BEGIN CONTENT ---")
            print(msg.content)
            print(f"--- END CONTENT ---")
        
        # Create the result object
        result = {
            "id": chat[0],
            "title": chat[1],
            "messages": messages,
            "created_at": chat[3],
            "updated_at": chat[4]
        }
        
        # Dump the entire JSON response as a serializable version, but NEVER include system messages
        serializable_result = {
            "id": chat[0],
            "title": chat[1],
            "messages": [
                {"role": msg.role, "content": msg.content, "timestamp": getattr(msg, "timestamp", None)} 
                for msg in messages if msg.role != "system"  # Never expose system messages
            ],
            "created_at": chat[3],
            "updated_at": chat[4]
        }
        
        # Save JSON to variable first to avoid truncation in print statements
        json_response = json.dumps(serializable_result, ensure_ascii=False)
        
        print("JSON RESPONSE START >>>")
        # Print entire JSON response without any truncation
        with open("/tmp/debug_response.json", "w") as f:
            f.write(json_response)
        print(f"Full JSON written to /tmp/debug_response.json (length: {len(json_response)})")
        # Also print to console
        print(json_response)
        print("<<< JSON RESPONSE END")
        print("================================================\n")
        
        return result

async def list_chats(user_secret: str):
    """List all chats for a specific user."""
    async with aiosqlite.connect(DATABASE_PATH) as db:
        cursor = await db.execute(
            "SELECT id, title, created_at, updated_at FROM chats WHERE user_secret = ? ORDER BY updated_at DESC",
            (user_secret,)
        )
        chats = await cursor.fetchall()
        
        print(f"\n=== LISTING ALL CHATS ===")
        print(f"User secret: {user_secret}")
        print(f"Found {len(chats)} chats")
        for chat in chats:
            print(f"Chat ID: {chat[0]}, Title: {chat[1]}, Updated: {chat[3]}")
        print(f"=========================\n")
        
        return [
            {
                "id": chat[0],
                "title": chat[1],
                "created_at": chat[2],
                "updated_at": chat[3]
            }
            for chat in chats
        ]

async def delete_chat(chat_id: int, user_secret: str):
    """Delete a chat."""
    async with aiosqlite.connect(DATABASE_PATH) as db:
        # Verify the chat belongs to the user
        cursor = await db.execute(
            "SELECT id FROM chats WHERE id = ? AND user_secret = ?",
            (chat_id, user_secret)
        )
        chat = await cursor.fetchone()
        
        if not chat:
            return False
        
        # Delete the chat
        await db.execute("DELETE FROM chats WHERE id = ?", (chat_id,))
        await db.commit()
        
        return True
