#!/bin/bash

# Compile all Python files to .pyc files
echo "Compiling Python files to .pyc..."
python -m compileall /app/server/src

# Remove source files, keeping only .pyc files
echo "Removing source files..."
find /app/server/src -name "*.py" -type f -delete

echo "Compilation complete. Only .pyc files remain."