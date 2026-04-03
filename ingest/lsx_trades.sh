#!/bin/bash

LSX="/app/data/lsx_trades"

# Fetch releases from GitHub API and save to releases.json
curl -s "https://api.github.com/repos/kweinert/lsx_trades/releases" -o releases.json
if [ $? -ne 0 ]; then
    echo "Error: Failed to fetch releases from GitHub API"
    exit 1
fi

# Check if releases.json exists and is not empty
if [ ! -s releases.json ]; then
    echo "Error: releases.json is empty or does not exist"
    exit 1
fi

# Create LSX directory if it doesn't exist
mkdir -p "$LSX"
if [ $? -ne 0 ]; then
    echo "Error: Failed to create directory $LSX"
    exit 1
fi

# Extract csv.gz assets and their URLs using jq
mapfile -t assets < <(jq -r '.[] | .assets[] | select(.name | endswith(".csv.gz")) | [.name, .browser_download_url] | join(" ")' releases.json)
if [ ${#assets[@]} -eq 0 ]; then
    echo "No .csv.gz files found in releases"
    exit 0
fi

# Process each asset
for asset in "${assets[@]}"; do
    # Split asset string into name and URL
    name=$(echo "$asset" | cut -d' ' -f1)
    url=$(echo "$asset" | cut -d' ' -f2-)
    
    # Export as environment variables
    #export "ASSET_${name//./_}"="$url"
    
    # Check if file exists in LSX directory
    if [ ! -f "$LSX/$name" ]; then
        echo "Downloading $name..."
        curl -s -L "$url" -o "$LSX/$name"
        if [ $? -ne 0 ]; then
            echo "Error: Failed to download $name from $url"
        else
            echo "Successfully downloaded $name to $LSX/"
        fi
    else
        echo "$name already exists in $LSX/, skipping download"
    fi
done

echo "Processing complete"
