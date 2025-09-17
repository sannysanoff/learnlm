#!/bin/bash

# Check if GEMINI_API_KEY environment variable is set
if [ -z "$GEMINI_API_KEY" ]; then
    echo "Error: GEMINI_API_KEY environment variable is not set"
    echo "Usage: GEMINI_API_KEY=your_api_key_here ./generate_api_key.sh"
    exit 1
fi

# Create the obfuscated API key module
API_KEY_MODULE="server/src/ky.py"

# Create directory if it doesn't exist
mkdir -p "$(dirname "$API_KEY_MODULE")"

# Generate Python code with base64 encoded chunks
cat > "$API_KEY_MODULE" << 'EOF'
# Auto-generated API key module - DO NOT COMMIT TO VERSION CONTROL
# This file contains obfuscated API key for Gemini service
import base64

def ky():
    # Base64 encoded chunks of the API key
    ch = [
EOF

# Convert API key to base64 and split into 2-character chunks
ENCODED_KEY=$(echo -n "$GEMINI_API_KEY" | base64)
CHUNKS=()
for (( i=0; i<${#ENCODED_KEY}; i+=2 )); do
    CHUNK="${ENCODED_KEY:$i:2}"
    CHUNKS+=("'$CHUNK'")
done

# Write chunks to the Python file
printf "        %s,\n" "${CHUNKS[@]}" >> "$API_KEY_MODULE"

# Add the rest of the function
cat >> "$API_KEY_MODULE" << 'EOF'
    ]
    # Concatenate all chunks and decode
    encoded = ''.join(ch)
    return base64.b64decode(encoded).decode('utf-8')
EOF

echo "Generated obfuscated API key module at $API_KEY_MODULE"
echo "IMPORTANT: This file contains sensitive information and should not be committed to version control"