#!/bin/bash

# AWS function name is defined in metadata.json
FUNCTION_NAME=$(cat metadata.json | jq '.function' --raw-output)

# Install virtual environment
#sudo apt-get install -y jq
#sudo pip install lambkin virtualenv

# Install dependcies and such
lambkin build

# Choose AWS profile
#export AWS_PROFILE=

# Publish the function
lambkin publish --role "lambda_basic_execution"

# Test if the function works bu running it
# lambkin run

# Define function's run schedule
lambkin schedule --rate '1 day'
