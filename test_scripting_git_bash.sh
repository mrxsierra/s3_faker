#!/bin/bash

# Start localstack in a new terminal

# Get the current directory
current_dir=$(pwd)
echo $current_dir

# Open Docker Desktop on Windows
start "powershell" -command & "C:\Program Files\Docker\Docker\Docker Desktop.exe"

# Start localstack in a new terminal and change to the current directory
start powershell -NoExit -Command "echo $current_dir; cd $(cygpath -w $current_dir); ls; localstack start; exit"

# Wait for localstack to start
while ! awslocal s3 ls > /dev/null 2>&1; do
  sleep 1
done

# Finallly create bucket than test app.py and stop localstack
awslocal s3 mb s3://mamoke-bucket; python app.py; localstack stop;
