#!/bin/sh
. .venv/bin/activate
python -m src.main -d ../learnlm/build/web "$@"
