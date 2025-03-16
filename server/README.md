# LLM Chat API Server

A backend server that implements a chat interface for Google's Gemini LLM API.

## Features

- REST API endpoint for synchronous chat completions
- WebSocket endpoint for streaming chat completions
- Full chat history management with context
- Support for system messages
- Parameter customization (temperature, top_p, top_k, max_tokens)

## Chat Message Format

The API uses a simple and flexible JSON format for chat history:

```json
{
  "history": {
    "system_message": "You are a helpful AI assistant.",
    "messages": [
      {
        "role": "user",
        "content": "Hello!"
      },
      {
        "role": "assistant", 
        "content": "Hi there! How can I help you today?"
      },
      {
        "role": "user",
        "content": "What's the weather like?"
      }
    ]
  },
  "temperature": 1.0,
  "top_p": 0.95,
  "top_k": 64,
  "max_tokens": 8192
}
```

## Setup

1. Clone the repository
2. Install dependencies:
   ```
   pip install -r requirements.txt
   ```
3. Set up your Google API key:
   ```
   export GEMINI_API_KEY=your_api_key_here
   ```

## Running the Server

Start the server:

```
python -m src.main
```

The server will be available at:
- REST API: http://localhost:8000/api/chat/completion
- WebSocket API: ws://localhost:8000/api/chat/completion/stream

## API Endpoints

### REST API: `/api/chat/completion`

- Method: POST
- Description: Generate a chat completion synchronously
- Request Body: ChatRequest object (see format above)
- Response: JSON with response text

### WebSocket API: `/api/chat/completion/stream`

- Description: Stream chat completion responses in real-time
- Message Format: ChatRequest object (see format above)
- Response: JSON with chunks of the response

## Testing

To test the WebSocket streaming functionality:

```
python tests/test_websocket_client.py
```

Make sure the server is running before executing the test script.