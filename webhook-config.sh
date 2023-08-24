#!/bin/bash
set -e

# get current working directory
WORKING_DIR=$(pwd)

# hooks sample file
hooks_sample_file="$WORKING_DIR/webhook/hooks.yaml.sample"

# Check if hooks sample file exists
if [ -e "$hooks_sample_file" ]; then
    
    # new hooks files
    hooks_file="$WORKING_DIR/webhook/hooks.yaml"

    # replace WORKING_DIR
    hooks_yaml_c=$(sed "s?WORKING_DIR?$WORKING_DIR?g" $hooks_sample_file)

    # write out hooks_file
    echo "$hooks_yaml_c" >$hooks_file

else
    echo "Sample hooks file does not exist: $hooks_sample_file"
    exit 1
fi
